"use strict";

const { spawn } = require("child_process");
const { Client } = require("pg");

const schemaSql = `
  CREATE TABLE IF NOT EXISTS "courses" (
    "id" serial PRIMARY KEY NOT NULL,
    "title" text NOT NULL,
    "image_src" text NOT NULL
  );

  CREATE TABLE IF NOT EXISTS "units" (
    "id" serial PRIMARY KEY NOT NULL,
    "title" text NOT NULL,
    "description" text NOT NULL,
    "course_id" integer NOT NULL,
    "order" integer NOT NULL
  );

  DO $$ BEGIN
    CREATE TYPE "type" AS ENUM('SELECT', 'ASSIST', 'VIDEO_LEARN', 'VIDEO_SELECT', 'SIGN_DETECT');
  EXCEPTION WHEN duplicate_object THEN NULL; END $$;

  CREATE TABLE IF NOT EXISTS "lessons" (
    "id" serial PRIMARY KEY NOT NULL,
    "title" text NOT NULL,
    "unit_id" integer NOT NULL,
    "order" integer NOT NULL
  );

  CREATE TABLE IF NOT EXISTS "challenges" (
    "id" serial PRIMARY KEY NOT NULL,
    "lesson_id" integer NOT NULL,
    "type" "type" NOT NULL,
    "question" text NOT NULL,
    "order" integer NOT NULL,
    "video_url" text
  );

  CREATE TABLE IF NOT EXISTS "challenge_options" (
    "id" serial PRIMARY KEY NOT NULL,
    "challenge_id" integer NOT NULL,
    "text" text NOT NULL,
    "correct" boolean NOT NULL
  );

  CREATE TABLE IF NOT EXISTS "challenge_progress" (
    "id" serial PRIMARY KEY NOT NULL,
    "user_id" text NOT NULL,
    "challenge_id" integer NOT NULL,
    "completed" boolean DEFAULT false NOT NULL,
    "retry_count" integer DEFAULT 0 NOT NULL,
    "time_spent_seconds" integer DEFAULT 0
  );

  CREATE TABLE IF NOT EXISTS "user_progress" (
    "user_id" text PRIMARY KEY NOT NULL,
    "user_name" text DEFAULT 'User' NOT NULL,
    "user_image_src" text DEFAULT '/mascot.svg' NOT NULL,
    "active_course_id" integer,
    "points" integer DEFAULT 0 NOT NULL
  );

  CREATE TABLE IF NOT EXISTS "lesson_analytics" (
    "id" serial PRIMARY KEY NOT NULL,
    "user_id" text NOT NULL,
    "lesson_id" integer NOT NULL,
    "completed_at" timestamp DEFAULT now() NOT NULL,
    "total_challenges" integer NOT NULL,
    "correct_first_try" integer DEFAULT 0 NOT NULL,
    "total_retries" integer DEFAULT 0 NOT NULL,
    "total_time_seconds" integer NOT NULL,
    "points_earned" integer NOT NULL,
    "challenge_details" text,
    "ai_feedback" text,
    "type_performance" text,
    "performance_trend" text,
    "first_half_accuracy" text,
    "second_half_accuracy" text,
    "time_pattern" text
  );

  CREATE TABLE IF NOT EXISTS "notification_preferences" (
    "user_id" text PRIMARY KEY NOT NULL,
    "reminder_enabled" boolean DEFAULT true NOT NULL,
    "reminder_time" text DEFAULT '19:00' NOT NULL,
    "timezone" text DEFAULT 'America/New_York' NOT NULL,
    "last_reminder_sent" timestamp
  );
`;

// Suppress the noisy SSL warning from pg.
const originalWarn = console.warn;
console.warn = (...args) => {
  if (args[0] && args[0].includes && args[0].includes("SSL modes")) return;
  originalWarn(...args);
};

function createDatabaseClient(connectionString) {
  return new Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
  });
}

async function ensureSchema(client) {
  await client.query(schemaSql);
}

async function copyFromSourceToTarget(sourceDatabaseUrl, targetDatabaseUrl) {
  return new Promise((resolve, reject) => {
    const dump = spawn(
      "pg_dump",
      [
        "--clean",
        "--if-exists",
        "--no-owner",
        "--no-privileges",
        "--dbname",
        sourceDatabaseUrl,
      ],
      {
        stdio: ["ignore", "pipe", "pipe"],
        env: process.env,
      }
    );

    const restore = spawn(
      "psql",
      ["--dbname", targetDatabaseUrl],
      {
        stdio: ["pipe", "pipe", "pipe"],
        env: process.env,
      }
    );

    let dumpError = "";
    let restoreError = "";

    dump.stdout.pipe(restore.stdin);

    dump.stderr.on("data", (chunk) => {
      dumpError += chunk.toString();
      process.stderr.write(chunk);
    });

    restore.stderr.on("data", (chunk) => {
      restoreError += chunk.toString();
      process.stderr.write(chunk);
    });

    dump.on("error", reject);
    restore.on("error", reject);

    dump.on("close", (dumpCode) => {
      if (dumpCode !== 0) {
        reject(
          new Error(
            `pg_dump exited with code ${dumpCode}${dumpError ? `: ${dumpError.trim()}` : ""}`
          )
        );
        return;
      }

      restore.stdin.end();
    });

    restore.on("close", (restoreCode) => {
      if (restoreCode !== 0) {
        reject(
          new Error(
            `psql exited with code ${restoreCode}${restoreError ? `: ${restoreError.trim()}` : ""}`
          )
        );
        return;
      }

      resolve();
    });
  });
}

async function main() {
  const targetDatabaseUrl = process.env.DATABASE_URL;
  const sourceDatabaseUrl = process.env.SOURCE_DATABASE_URL;
  const client = createDatabaseClient(targetDatabaseUrl);

  try {
    await client.connect();

    console.log("✅ Connected to target database");

    if (sourceDatabaseUrl) {
      console.log(
        "🔄 Source database detected. Copying schema and data in one step..."
      );
      await copyFromSourceToTarget(sourceDatabaseUrl, targetDatabaseUrl);
      console.log("✅ Source database copied successfully");
      return;
    }

    console.log(
      "📦 No source database provided. Ensuring target schema exists..."
    );
    await ensureSchema(client);
    console.log("✅ Tables created or already present");
  } catch (err) {
    if (
      err.code === "ENOTFOUND" ||
      err.code === "ECONNREFUSED" ||
      err.code === "ETIMEDOUT"
    ) {
      console.error("⚠️  Database not reachable:", err.message);
      process.exit(1);
    } else {
      console.error("❌ Migration error:", err.message);
      process.exit(1);
    }
  } finally {
    await client.end();
  }
}

main();

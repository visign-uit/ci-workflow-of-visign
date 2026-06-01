import { Client } from "pg";
import "dotenv/config";
import { Pool } from "pg";

// Suppress the SSL warning
const originalWarn = console.warn;
console.warn = (...args) => {
  if (args[0] && args[0].includes && args[0].includes('SSL modes')) return;
  originalWarn(...args);
};

const { Pool: PgPool } = require("pg");

async function main() {
  try {
    // Database configuration
    const pool = new PgPool({
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false }
    });

    // Check what tables exist
    const client = new Client({
      connectionString: process.env.DATABASE_URL,
      ssl: { rejectUnauthorized: false }
    });

    await client.connect();

    const tables = await client.query(
      "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public'"
    );

    console.log('Current tables in database:', tables.rows.map(r => r.table_name));

    if (tables.rows.length === 0) {
      console.log('\nNo tables found! Running migration...\n');

      const sql = \`
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

        CREATE TYPE "type" AS ENUM('SELECT', 'ASSIST', 'VIDEO_LEARN', 'VIDEO_SELECT', 'SIGN_DETECT');

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
      \`;

      await client.query(sql);
      console.log('Tables created successfully!');
    } else {
      console.log('Tables already exist.');
    }

  } catch (err) {
    if (err.code === 'ENOTFOUND' || err.code === 'ECONNREFUSED' || err.code === 'ETIMEDOUT') {
      console.log('⚠️  Database not reachable yet:', err.message);
      console.log('Migration will be retried on next startup.');
    } else {
      console.error('❌ Error:', err.message);
    }
  } finally {
    await client.end();
  }
}

main();
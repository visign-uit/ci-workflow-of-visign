import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import "dotenv/config";
import * as fs from "fs";
import { parse } from "csv-parse/sync";
import * as schema from "@/db/schema";   // giữ nguyên

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const db = drizzle(pool, { schema });

const main = async () => {
  try {
    console.log("🎬 Seeding Vietnamese Sign Language database...");

    // Read CSV file
    const fileContent = fs.readFileSync(
      "./classified_data_with_levels.csv",
      "utf-8"
    );
    const records = parse(fileContent, {
      columns: true,
      skip_empty_lines: true,
    });

    console.log(`📊 Found ${records.length} signs in CSV`);

    // Delete all existing data
    console.log("🗑️  Deleting existing data...");
    await Promise.all([
      db.delete(schema.challengeProgress),
      db.delete(schema.challengeOptions),
      db.delete(schema.challenges),
      db.delete(schema.lessons),
      db.delete(schema.units),
      db.delete(schema.courses),
      db.delete(schema.userProgress),
    ]);

    // Create course
    const [course] = await db
      .insert(schema.courses)
      .values([
        {
          title: "Vietnamese Sign Language",
          imageSrc: "/vn.svg",
        },
        {
          title: "Spanish Sign Language",
          imageSrc: "/es.svg",
        },
        {
          title: "French Sign Language",
          imageSrc: "/fr.svg",
        },
        {
          title: "Croatian Sign Language",
          imageSrc: "/hr.svg",
        },
        {
          title: "Italian Sign Language",
          imageSrc: "/it.svg",
        },
        {
          title: "Japanese Sign Language",
          imageSrc: "/jp.svg",
        }
      ])
      .returning();

    console.log(`✅ Created course: ${course.title}`);

    // Group data by TOPIC (Unit) and LEVEL (Lesson)
    const groupedData: Record<string, Record<number, any[]>> = {};

    for (const row of records) {
      const topic = (row as Record<string, string>).TOPIC;
      const level = parseInt((row as Record<string, string>).LEVEL);

      if (!groupedData[topic]) groupedData[topic] = {};
      if (!groupedData[topic][level]) groupedData[topic][level] = [];

      groupedData[topic][level].push(row);
    }

    let unitOrder = 1;

    // Create Units and Lessons
    for (const [topicName, levels] of Object.entries(groupedData)) {
      console.log(`📚 Creating unit: ${topicName}`);

      const [unit] = await db
        .insert(schema.units)
        .values([
          {
            courseId: course.id,
            title: topicName,
            description: `Học ${topicName} bằng ngôn ngữ ký hiệu`,
            order: unitOrder++,
          },
        ])
        .returning();

      // Create lessons for each level
      for (const [levelStr, signs] of Object.entries(levels)) {
        const level = parseInt(levelStr);
        console.log(
          `  📖 Creating lesson: Level ${level} (${signs.length} signs)`
        );

        const [lesson] = await db
          .insert(schema.lessons)
          .values([
            {
              unitId: unit.id,
              title: `Cấp độ ${level}`,
              order: level,
            },
          ])
          .returning();

        let challengeOrder = 1;

        // Process signs in groups of 3 (since each lesson = 9 challenges from 3 signs)
        // Each group of 3 signs creates: 3 VIDEO_LEARN + 3 VIDEO_SELECT + 3 SIGN_DETECT = 9 challenges
        for (let i = 0; i < signs.length; i += 3) {
          const signGroup = signs.slice(i, Math.min(i + 3, signs.length));

          // Need exactly 3 signs for a complete lesson
          if (signGroup.length < 3) continue;

          // === PHASE 1: VIDEO_LEARN (3 challenges) ===
          // User watches videos to learn the signs
          for (const sign of signGroup) {
            await db.insert(schema.challenges).values({
              lessonId: lesson.id,
              type: "VIDEO_LEARN",
              question: sign.LABEL,
              order: challengeOrder++,
              videoUrl: sign.VIDEO_URL,
            });
          }

          // === PHASE 2: VIDEO_SELECT (3 challenges) ===
          // Show video, user picks correct answer from 3 text options
          for (let j = 0; j < signGroup.length; j++) {
            const correctSign = signGroup[j];
            const wrongOptions = signGroup.filter((_, idx) => idx !== j);

            const [challenge] = await db
              .insert(schema.challenges)
              .values({
                lessonId: lesson.id,
                type: "VIDEO_SELECT",
                question: "Dấu hiệu này có nghĩa là gì?",
                order: challengeOrder++,
                videoUrl: correctSign.VIDEO_URL,
              })
              .returning();

            // Create 3 options: 1 correct + 2 wrong (shuffle them)
            const allOptions = [
              { sign: correctSign, correct: true },
              { sign: wrongOptions[0], correct: false },
              { sign: wrongOptions[1], correct: false },
            ].sort(() => Math.random() - 0.5);

            for (const option of allOptions) {
              await db.insert(schema.challengeOptions).values({
                challengeId: challenge.id,
                text: option.sign.LABEL,
                correct: option.correct,
              });
            }
          }

          // === PHASE 3: SIGN_DETECT (3 challenges) ===
          // User performs the sign, detected by MediaPipe + CV model
          for (const sign of signGroup) {
            await db.insert(schema.challenges).values({
              lessonId: lesson.id,
              type: "SIGN_DETECT",
              question: `Thực hiện dấu hiệu: "${sign.LABEL}"`,
              order: challengeOrder++,
              videoUrl: sign.VIDEO_URL,
            });
          }
        }

        console.log(
          `    ✅ Created ${challengeOrder - 1} challenges for level ${level}`
        );
      }
    }

    console.log("🎉 Seeding completed successfully!");
    console.log(`📊 Summary:`);
    console.log(`   - Total signs processed: ${records.length}`);
    console.log(`   - Topics (Units): ${Object.keys(groupedData).length}`);
  } catch (error) {
    console.error("❌ Error seeding database:", error);
    throw new Error("Failed to seed database");
  }
};

void main();

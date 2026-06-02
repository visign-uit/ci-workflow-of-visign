import postgres from "postgres";
import { drizzle } from "drizzle-orm/postgres-js";

import * as schema from "./schema";

if (!process.env.DATABASE_URL) {
  throw new Error("Missing required environment variable: DATABASE_URL");
}

export const sql = postgres(process.env.DATABASE_URL, {
  max: 1,
  ssl: "require",
});

export const db = drizzle(sql, { schema });

export default db;
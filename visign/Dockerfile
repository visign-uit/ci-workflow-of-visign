# ============================================
# Stage 1: Dependencies Installation Stage
# ============================================
ARG NODE_VERSION=20-alpine

FROM node:${NODE_VERSION} AS dependencies

WORKDIR /app

COPY package.json package-lock.json* ./

RUN --mount=type=cache,target=/root/.npm \
    npm ci --no-audit --no-fund


# ============================================
# Stage 2: Database Migration Image for K8s Job
# ============================================
FROM node:${NODE_VERSION} AS migrator

WORKDIR /app

ENV NODE_ENV=production

# Optional: keep this only if your scripts need psql/pg tools.
RUN apk add --no-cache postgresql-client

COPY --from=dependencies /app/node_modules ./node_modules

COPY . .

USER node

CMD ["npm", "run", "db:migrate"]


# ============================================
# Stage 3: Build Next.js application in standalone mode
# ============================================
FROM node:${NODE_VERSION} AS builder

WORKDIR /app

COPY --from=dependencies /app/node_modules ./node_modules

COPY . .

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

ARG NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
ARG DATABASE_URL

ENV NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=${NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY}
ENV DATABASE_URL=${DATABASE_URL:-postgres://dummy:dummy@localhost:5432/dummy}

RUN test -n "$NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" || \
    (echo "ERROR: NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY is required" && exit 1)

RUN --mount=type=cache,target=/app/.next/cache \
    npm run build


# ============================================
# Stage 4: Run Next.js application
# ============================================
FROM node:${NODE_VERSION} AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"
ENV NEXT_TELEMETRY_DISABLED=1

COPY --from=builder /app/public ./public

RUN mkdir .next && chown node:node .next

COPY --from=builder --chown=node:node /app/.next/standalone ./
COPY --from=builder --chown=node:node /app/.next/static ./.next/static

USER node

EXPOSE 3000

CMD ["node", "server.js"]
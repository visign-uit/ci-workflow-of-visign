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
# Stage 2: Build Next.js application in standalone mode
# ============================================
FROM node:${NODE_VERSION} AS builder

WORKDIR /app

COPY --from=dependencies /app/node_modules ./node_modules

COPY . .

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# CLERK KEY: bắt buộc truyền lúc build (bị bake vào JS bundle bởi Next.js).
# Không có fallback → nếu CI quên truyền thì build fail ngay thay vì
# deploy prod với key sai môi trường.
ARG NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
ENV NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=${NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY}
RUN test -n "$NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY" || \
    (echo "ERROR: NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY is required" && exit 1)

# DATABASE_URL không cần lúc build — K8s inject runtime qua secretKeyRef.
# Nếu project chạy "prisma generate" trong npm run build thì cần thêm lại:
#   ARG DATABASE_URL
#   ENV DATABASE_URL=${DATABASE_URL:-postgres://dummy:dummy@localhost:5432/dummy}

RUN --mount=type=cache,target=/app/.next/cache \
    npm run build

# ============================================
# Stage 3: Run Next.js application
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
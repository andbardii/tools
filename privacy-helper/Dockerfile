FROM node:22-bookworm-slim AS builder
RUN apt-get update && apt-get install -y --no-install-recommends python3 make g++ && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package*.json ./
COPY src/server/package*.json ./src/server/
RUN npm ci --ignore-scripts && npm ci --prefix src/server
COPY . .
RUN npm run build && npm run build --prefix src/server && npm prune --omit=dev --prefix src/server

FROM node:22-bookworm-slim AS runner
RUN apt-get update && apt-get install -y --no-install-recommends sqlite3 curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/src/server/dist ./src/server/dist
COPY --from=builder /app/src/server/node_modules ./src/server/node_modules
COPY src/server/package.json ./src/server/package.json
RUN mkdir -p /app/data && chown -R node:node /app/data
USER node
ENV HOST=0.0.0.0 NODE_ENV=production PORT=3000 DATA_DIR=/app/data LOG_DIR=/app/data/logs BACKUP_DIR=/app/data/backups
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD curl -f http://localhost:3000/api/health || exit 1
CMD ["node", "src/server/dist/server/index.js"]

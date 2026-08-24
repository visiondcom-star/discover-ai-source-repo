# ---- deps: deterministic install from the lockfile ----
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# ---- development: hot-reload server used by docker-compose.yml ----
FROM deps AS development
COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]

# ---- builder: production build (output: 'standalone' in next.config.mjs) ----
FROM deps AS builder
COPY . .
# BACKEND_URL is evaluated by next.config.mjs rewrites() at BUILD time and
# baked into the routes manifest; it must match the API service name in the
# Docker network ("backend"), not a browser-visible URL.
ENV NEXT_TELEMETRY_DISABLED=1
ENV BACKEND_URL=http://backend:8000
RUN npm run build

# ---- runner: minimal non-root production image ----
FROM node:20-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    HOSTNAME=0.0.0.0 \
    PORT=3000 \
    NEXT_TELEMETRY_DISABLED=1
RUN addgroup --system --gid 1001 nodejs && adduser --system --uid 1001 nextjs
# No public/ directory in this project; standalone output + static assets only.
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
USER nextjs
EXPOSE 3000
CMD ["node", "server.js"]

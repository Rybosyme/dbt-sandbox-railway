FROM node:22-alpine

WORKDIR /app

RUN corepack enable

COPY packages/api/package.json ./package.json
COPY packages/api/pnpm-lock.yaml ./pnpm-lock.yaml
COPY packages/api/tsconfig.json ./tsconfig.json
COPY packages/api/drizzle.config.ts ./drizzle.config.ts

RUN pnpm install --frozen-lockfile

COPY packages/api/src ./src
COPY packages/api/drizzle ./drizzle

RUN pnpm build

EXPOSE 3000

CMD ["node", "dist/index.js"]

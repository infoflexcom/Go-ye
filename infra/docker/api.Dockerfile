FROM node:22-bookworm-slim AS dependencies
WORKDIR /workspace
COPY package.json package-lock.json ./
COPY backend/package.json ./backend/package.json
RUN npm ci --ignore-scripts

FROM dependencies AS development
COPY backend ./backend
WORKDIR /workspace/backend
EXPOSE 3000
CMD ["npm", "run", "start:dev"]

FROM dependencies AS build
COPY backend ./backend
RUN npm run build --workspace=@goye/backend

FROM node:22-bookworm-slim AS production-dependencies
WORKDIR /workspace
COPY package.json package-lock.json ./
COPY backend/package.json ./backend/package.json
RUN npm ci --omit=dev --ignore-scripts

FROM node:22-bookworm-slim AS production
ENV NODE_ENV=production
WORKDIR /app
COPY --from=production-dependencies /workspace/backend/node_modules ./node_modules
COPY --from=build /workspace/backend/package.json ./package.json
COPY --from=build /workspace/backend/dist ./dist
COPY --from=build /workspace/backend/migrations ./migrations
EXPOSE 3000
CMD ["node", "dist/main.js"]

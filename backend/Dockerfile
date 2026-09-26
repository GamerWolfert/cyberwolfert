FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY src ./src
COPY schema.sql version.json custom_links.json ./
RUN mkdir -p uploads public downloads
ENV NODE_ENV=production
EXPOSE 43711
CMD ["node", "src/server.js"]

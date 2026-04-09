# Static site: single index.html served by nginx on port 3000
# Port 3000 matches the Traefik template convention (see deployment guide).
FROM nginx:alpine

# wget is needed for the Docker healthcheck
RUN apk add --no-cache wget

# Replace the default nginx config with our own (listens on 3000)
COPY nginx.conf /etc/nginx/nginx.conf

# Remove default nginx content so only our file is served
RUN rm -f /usr/share/nginx/html/index.html /usr/share/nginx/html/50x.html

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=5s --start-period=15s --retries=3 \
  CMD wget --spider -q http://localhost:3000/ || exit 1

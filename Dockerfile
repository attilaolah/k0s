FROM nginx:1.27.4-alpine

RUN rm /usr/share/nginx/html/*.html && \
    sed -i "s|^pid\b.*|pid /var/run/nginx/nginx.pid;|" /etc/nginx/nginx.conf && \
    sed -i "s|^worker_processes\b.*|worker_processes 2;|" /etc/nginx/nginx.conf && \
    sed -i "/^user\b/d" /etc/nginx/nginx.conf && \
    apk update && apk add --no-cache curl

COPY --chown=nginx:nginx keys/attila@dorn.haus-67093be0.rsa.pub /usr/share/nginx/html/key.rsa.pub
COPY --chown=nginx:nginx nginx.conf /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx dist/ /usr/share/nginx/html/

USER nginx
EXPOSE 8443

CMD ["nginx", "-g", "daemon off;"]

ARG VERSION
LABEL org.opencontainers.image.title="K0s APK mirror" \
      org.opencontainers.image.description="Secure APK mirror containing a static k0s package." \
      org.opencontainers.image.authors="Attila Oláh <attila@dorn.haus>" \
      org.opencontainers.image.version="$VERSION" \
      org.opencontainers.image.source="https://github.com/attilaolah/k0s"

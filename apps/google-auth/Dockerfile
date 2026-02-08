FROM thomseddon/traefik-forward-auth:2 AS app
FROM alpine:3
RUN apk add --no-cache wget
COPY --from=app /traefik-forward-auth /traefik-forward-auth
ENTRYPOINT ["/traefik-forward-auth"]

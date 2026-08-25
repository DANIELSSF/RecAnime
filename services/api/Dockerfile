# syntax=docker/dockerfile:1
FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/api ./cmd/api

# distroless/static ships CA certificates; time zone data is embedded in the binary (time/tzdata).
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/api /api
ENV PORT=8080 APP_ENV=production
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/api", "serve"]

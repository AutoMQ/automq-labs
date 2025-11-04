# Use the official Golang image to create a build artifact.
# This is known as a multi-stage build.
FROM golang:1.23 AS builder

WORKDIR /app

# Copy the go.mod and go.sum files
COPY go_producer/go.mod .
COPY go_producer/go.sum .

# Download all dependencies
RUN go mod download

# Copy the source code
COPY go_producer/main.go .

# Ensure all dependencies are resolved and go.sum is correct
RUN go mod tidy

# Build the Go app
RUN CGO_ENABLED=0 GOOS=linux go build -o /go-producer

# Start a new stage from scratch for a smaller image
FROM alpine:latest

WORKDIR /root/

# Copy the Pre-built binary file from the previous stage
COPY --from=builder /go-producer .

# Command to run the executable
CMD ["/root/go-producer"]
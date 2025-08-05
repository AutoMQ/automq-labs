# Build stage
FROM golang:1.21-alpine AS builder

# Install git for go mod download
RUN apk add --no-cache git

# Set working directory
WORKDIR /app

# Copy go mod files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy source code
COPY . .

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o automq-go-examples .

# Final stage
FROM alpine:latest

# Install ca-certificates and bash for HTTPS requests and script execution
RUN apk --no-cache add ca-certificates tzdata bash

# Create a non-root user for security
RUN addgroup -g 1001 appgroup && \
    adduser -D -u 1001 -G appgroup appuser

# Set working directory
WORKDIR /app

# Copy the binary from builder stage
COPY --from=builder /app/automq-go-examples .

# Copy the run script
COPY run-examples.sh ./bin/

# Make the script executable
RUN chmod +x ./bin/run-examples.sh

# Change ownership of the app directory
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Default command to run the examples
CMD ["./bin/run-examples.sh"]
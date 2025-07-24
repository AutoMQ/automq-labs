FROM docker.io/debian:bookworm

# Install Maven
RUN apt-get update && apt-get install -y maven openjdk-17-jdk

# Set working directory
WORKDIR /app

# Copy source code and scripts
COPY . .

# Make the script executable
RUN chmod +x ./bin/run-examples.sh

# Build the project with dependencies (skip tests, force update)
RUN mvn clean install -U -Dmaven.test.skip=true

# Set environment variables
ENV JAVA_OPTS="-Xmx512m -Xms256m"

# Create a non-root user for security
RUN groupadd -g 1001 appgroup && \
    useradd -r -u 1001 -g appgroup appuser

# Change ownership of the app directory
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Default command to run the examples
CMD ["./bin/run-examples.sh"]
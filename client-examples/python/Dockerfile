FROM python:3.11-slim

# Set working directory
WORKDIR /app

# No additional system dependencies needed for kafka-python
# kafka-python is a pure Python implementation that doesn't require librdkafka

# Copy requirements first for better caching
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY . .

# Make the run script executable
RUN chmod +x run_examples.py

# Set environment variables
ENV PYTHONPATH=/app
ENV PYTHONUNBUFFERED=1

# Create a non-root user for security
RUN groupadd -g 1001 appgroup && \
    useradd -r -u 1001 -g appgroup appuser

# Change ownership of the app directory
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Default command to run the examples
CMD ["python", "run_examples.py"]
# --- Stage 1: The Builder ---
# This stage compiles the Rust application into a static binary.
FROM rust:1.88-slim AS builder

# Set the working directory for the build.
WORKDIR /usr/src/app

# Install the MUSL target for the Rust toolchain.
RUN rustup target add x86_64-unknown-linux-musl

# ** FIX #3: Install build-essentials and the MUSL C compiler **
RUN apt-get update && apt-get install -y musl-tools build-essential pkg-config libssl-dev

# Copy manifests and source code to leverage Docker's layer caching.
COPY Cargo.toml Cargo.lock ./
COPY src ./src

# Fetch dependencies.
RUN cargo fetch

# Copy the rest of the project files.
COPY . .

# Build the application in release mode, targeting MUSL.
RUN cargo build --release --target x86_64-unknown-linux-musl

# --- Stage 2: The Runtime ---
# This stage creates the final, minimal image for deployment.
FROM debian:bookworm-slim

# Set the working directory for the running container.
WORKDIR /app

# Copy the compiled, static binary from the builder stage.
COPY --from=builder /usr/src/app/target/x86_64-unknown-linux-musl/release/cloud-native-gauntlet .

# Copy the migrations folder.
COPY ./migrations ./migrations

# Expose the port.
EXPOSE 8000

# Set the command to run when the container starts, using a shell.
ENV RUST_LOG=info
CMD ["/bin/sh", "-c", "./cloud-native-gauntlet"]
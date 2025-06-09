# Dockerfile in your project root

# Use a specific, stable Julia version as the base image.
# It's recommended to use a specific version (e.g., julia:1.10.0)
# to ensure consistent builds. You can change this to your Julia version.
FROM julia:1.11.5

# Set the working directory inside the container. All subsequent commands
# will be executed relative to this directory inside the Docker container.
WORKDIR /app

# Copy your Julia project's dependency files first. This allows Docker
# to cache this layer, so if only your source code changes (not dependencies),
# the build will be faster on subsequent deploys.
# `.` refers to the current directory on your local machine.
# `./` refers to the WORKDIR (`/app`) inside the container.
COPY Project.toml Manifest.toml ./

# Install Julia project dependencies. This command reads your Project.toml
# and Manifest.toml to install all necessary packages.
# `--project=.` ensures Julia uses the package environment defined in the current directory.
RUN julia --project=. -e 'using Pkg; Pkg.instantiate()'

# Copy your Julia application source code.
# Ensure all necessary Julia files (server.jl, checking.jl, etc.) are copied.
COPY server.jl ./
COPY checking.jl ./
# If you have other Julia source files in subdirectories (e.g., `src/`),
# you would add more COPY commands like:
# COPY src/ ./src/

# Expose the port that your Julia server will listen on.
# This must match the `port` variable in your `server.jl` (default is 8000).
EXPOSE 8000

# Define the command to run your Julia server when the Docker container starts.
# `CMD` is preferred over `ENTRYPOINT` as it allows for easier overriding if needed.
# It tells the container to execute `julia` with the specified project environment
# and then run your main server script.
CMD ["julia", "--project=.", "server.jl"]
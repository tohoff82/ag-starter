#!/usr/bin/env bash

set -euo pipefail

# Usage: agent name is the only required parameter
if [[ $# -eq 0 || ${1-} == "-h" || ${1-} == "--help" ]]; then
    cat <<USAGE
Usage: $(basename "$0") <agent-name>

Creates a new .NET Aspire agent solution with the following structure in the CURRENT directory:
    <cwd>/
        - src.sln
        - <agent>.Agent (aspire apphost)
        - <agent>.Agent.Cqrs (classlib)
        - <agent>.Y.Core (servicedefaults)
        - <agent>.Api.Endpoints (webapi)
        - <agent>.Mcp.Endpoints (webapi)
        - <agent>.Web.Endpoints (web)

Notes:
    - Solution name is fixed to 'src'.
    - All projects are created as sibling folders in the current directory.
    - currentdir is derived from the directory this script is executed in.
USAGE
    exit 0
fi

# Input (single parameter)
agentname="$1"

# Derived constants/variables
slnname="src"                      # solution name fixed to 'src'
currentdir="$(basename "${PWD}")"  # using the directory where script is executed
basepath="${PWD}"                   # generate everything in current folder

echo "Agent name: ${agentname}"
echo "Current dir: ${currentdir}"
echo "Base path: ${basepath}"

# Check .NET version (require 9.0.0+)
dotnet_version=$(dotnet --version)
required_version="9.0.0"
if [[ "$(printf '%s\n' "$required_version" "$dotnet_version" | sort -V | head -n1)" != "$required_version" ]]; then
    echo "Error: .NET ${required_version} or higher is required."
    echo "Current version: ${dotnet_version}"
    echo "Please upgrade .NET before running this script."
    exit 1
fi

# Check if the required Aspire templates are installed
echo "Checking if .NET Aspire templates are installed..."
aspire_apphost_template=$(dotnet new list | grep "aspire-apphost")
aspire_servicedefaults_template=$(dotnet new list | grep "aspire-servicedefaults")

if [[ -z "$aspire_apphost_template" || -z "$aspire_servicedefaults_template" ]]; then
    echo "Installing .NET Aspire templates..."
    dotnet workload install aspire
    
    # Double-check installation
    aspire_apphost_template=$(dotnet new list | grep "aspire-apphost")
    aspire_servicedefaults_template=$(dotnet new list | grep "aspire-servicedefaults")
    
    if [[ -z "$aspire_apphost_template" || -z "$aspire_servicedefaults_template" ]]; then
        echo "Error: Failed to install .NET Aspire templates. Please install them manually using 'dotnet workload install aspire'"
        exit 1
    else
        echo ".NET Aspire templates installed successfully."
    fi
else
    echo ".NET Aspire templates are already installed."
fi

# Create top-level files to keep the solution self-contained (in current directory)
if [[ ! -f "${basepath}/.gitignore" ]]; then
    dotnet new gitignore
fi
if [[ ! -f "${basepath}/.editorconfig" ]]; then
    dotnet new editorconfig
fi

# Create solution and projects
dotnet new sln -n "${slnname}"
dotnet new aspire-apphost -n "${agentname}.Agent" -o "${basepath}/${agentname}.Agent"
dotnet new classlib -n "${agentname}.Agent.Cqrs" -o "${basepath}/${agentname}.Agent.Cqrs"
dotnet new aspire-servicedefaults -n "${agentname}.Y.Core" -o "${basepath}/${agentname}.Y.Core"
dotnet new webapi -n "${agentname}.Api.Endpoints" -o "${basepath}/${agentname}.Api.Endpoints"
dotnet new webapi -n "${agentname}.Mcp.Endpoints" -o "${basepath}/${agentname}.Mcp.Endpoints"
dotnet new web -n "${agentname}.Web.Endpoints" -o "${basepath}/${agentname}.Web.Endpoints"

# Add projects to solution
dotnet sln "${basepath}/${slnname}.sln" add "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj" \
                                         "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj" \
                                         "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
                                         "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
                                         "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
                                         "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj"

# Helper to add one or more NuGet packages to a specific project
add_packages() {
    local csproj="$1"; shift || true
    for spec in "$@"; do
        local name version
        if [[ "$spec" == *"@"* ]]; then
            name="${spec%@*}"
            version="${spec#*@}"
            dotnet add "$csproj" package "$name" --version "$version"
        else
            dotnet add "$csproj" package "$spec"
        fi
    done
}

# Add common NuGet packages
add_packages "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj" \
    "MediatR@12.5.0"

add_packages "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "FluentValidation" \
    "FluentValidation.AspNetCore" \
    "Swashbuckle.AspNetCore"

add_packages "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "FluentValidation" \
    "FluentValidation.AspNetCore" \
    "Swashbuckle.AspNetCore"

# Helper to add project references
add_refs() {
    local target_csproj="$1"; shift || true
    for ref in "$@"; do
        dotnet add "$target_csproj" reference "$ref"
    done
}

# Add project references
add_refs "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj" \
    "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj" \
    "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj"

add_refs "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

add_refs "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

add_refs "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "${basepath}/${agentname}.Y.Core/${agentname}.Y.Core.csproj" \
    "${basepath}/${agentname}.Agent.Cqrs/${agentname}.Agent.Cqrs.csproj"

# Setup centralized configuration by linking appsettings from Agent to Endpoint projects
echo "Setting up centralized configuration with linked appsettings files..."

# Function to apply XML edits to add linked appsettings
apply_linked_appsettings() {
    local project_path="$1"
    local project_file="$(basename "$project_path")"
    
    # Create a temporary file for the new content
    local temp_file="${project_path}.temp"
    
    # Read the project file
    cat "$project_path" > "$temp_file"
    
    # Check if the linked settings already exist (to avoid duplicates)
    if ! grep -q "Link=\"appsettings.json\"" "$temp_file"; then
        # Find the closing </Project> tag and insert our ItemGroup before it
        sed -i '' -e '/<\/Project>/i\
  <!-- Linked appsettings files from Agent project -->\
  <ItemGroup>\
    <Content Remove="appsettings.json" />\
    <Content Remove="appsettings.Development.json" />\
    <Content Include="..\\'"${agentname}"'.Agent\/appsettings.json" Link="appsettings.json">\
      <CopyToOutputDirectory>PreserveNewest<\/CopyToOutputDirectory>\
    <\/Content>\
    <Content Include="..\\'"${agentname}"'.Agent\/appsettings.Development.json" Link="appsettings.Development.json">\
      <CopyToOutputDirectory>PreserveNewest<\/CopyToOutputDirectory>\
    <\/Content>\
  <\/ItemGroup>\
' "$temp_file"
    fi
    
    # Replace the original file
    mv "$temp_file" "$project_path"
}

# Apply linked appsettings to all endpoint projects
apply_linked_appsettings "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj"
apply_linked_appsettings "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj"
apply_linked_appsettings "${basepath}/${agentname}.Web.Endpoints/${agentname}.Web.Endpoints.csproj"

# Create basic CQRS structure
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Commands"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Queries"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Models"
mkdir -p "${basepath}/${agentname}.Agent.Cqrs/Handlers"

# Create example Command and Query files
cat > "${basepath}/${agentname}.Agent.Cqrs/Commands/ExampleCommand.cs" << EOF
using MediatR;

namespace ${agentname}.Agent.Cqrs.Commands
{
    public class ExampleCommand : IRequest<bool>
    {
        public string Data { get; set; } = string.Empty;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Queries/ExampleQuery.cs" << EOF
using MediatR;

namespace ${agentname}.Agent.Cqrs.Queries
{
    public class ExampleQuery : IRequest<string>
    {
        public string Id { get; set; } = string.Empty;
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Handlers/ExampleCommandHandler.cs" << EOF
using MediatR;
using ${agentname}.Agent.Cqrs.Commands;

namespace ${agentname}.Agent.Cqrs.Handlers
{
    public class ExampleCommandHandler : IRequestHandler<ExampleCommand, bool>
    {
        public Task<bool> Handle(ExampleCommand request, CancellationToken cancellationToken)
        {
            // Example implementation
            return Task.FromResult(true);
        }
    }
}
EOF

cat > "${basepath}/${agentname}.Agent.Cqrs/Handlers/ExampleQueryHandler.cs" << EOF
using MediatR;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Agent.Cqrs.Handlers
{
    public class ExampleQueryHandler : IRequestHandler<ExampleQuery, string>
    {
        public Task<string> Handle(ExampleQuery request, CancellationToken cancellationToken)
        {
            // Example implementation
            return Task.FromResult(\$"Response for ID: {request.Id}");
        }
    }
}
EOF

# Create sample controllers
mkdir -p "${basepath}/${agentname}.Api.Endpoints/Controllers"
cat > "${basepath}/${agentname}.Api.Endpoints/Controllers/ExampleController.cs" << EOF
using MediatR;
using Microsoft.AspNetCore.Mvc;
using ${agentname}.Agent.Cqrs.Commands;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Api.Endpoints.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class ExampleController : ControllerBase
    {
        private readonly IMediator _mediator;

        public ExampleController(IMediator mediator)
        {
            _mediator = mediator;
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(string id)
        {
            var query = new ExampleQuery { Id = id };
            var result = await _mediator.Send(query);
            return Ok(result);
        }

        [HttpPost]
        public async Task<IActionResult> Post([FromBody] ExampleCommand command)
        {
            var result = await _mediator.Send(command);
            return Ok(result);
        }
    }
}
EOF

mkdir -p "${basepath}/${agentname}.Mcp.Endpoints/Controllers"
cat > "${basepath}/${agentname}.Mcp.Endpoints/Controllers/ExampleController.cs" << EOF
using MediatR;
using Microsoft.AspNetCore.Mvc;
using ${agentname}.Agent.Cqrs.Commands;
using ${agentname}.Agent.Cqrs.Queries;

namespace ${agentname}.Mcp.Endpoints.Controllers
{
    [ApiController]
    [Route("mcp/[controller]")]
    public class ChatController : ControllerBase
    {
        private readonly IMediator _mediator;

        public ChatController(IMediator mediator)
        {
            _mediator = mediator;
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> Get(string id)
        {
            var query = new ExampleQuery { Id = id };
            var result = await _mediator.Send(query);
            return Ok(result);
        }

        [HttpPost]
        public async Task<IActionResult> Post([FromBody] ExampleCommand command)
        {
            var result = await _mediator.Send(command);
            return Ok(result);
        }
    }
}
EOF

# Update Program.cs files to include MediatR and Swagger
cat > "${basepath}/${agentname}.Api.Endpoints/Program.cs" << EOF
using System.Reflection;
using ${agentname}.Agent.Cqrs.Commands;
using MediatR;

var builder = WebApplication.CreateBuilder(args);

// Add defaults services to the container.
builder.AddServiceDefaults();

// Add services to the container.
builder.Services.AddControllers();

// Add MediatR
builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(ExampleCommand).Assembly));

// Add Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseHttpsRedirection();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthorization();
app.MapControllers();

app.Run();
EOF

cat > "${basepath}/${agentname}.Mcp.Endpoints/Program.cs" << EOF
using System.Reflection;
using ${agentname}.Agent.Cqrs.Commands;
using MediatR;

var builder = WebApplication.CreateBuilder(args);

// Add defaults services to the container.
builder.AddServiceDefaults();

// Add services to the container.
builder.Services.AddControllers();

// Add MediatR
builder.Services.AddMediatR(cfg => cfg.RegisterServicesFromAssembly(typeof(ExampleCommand).Assembly));

// Add Swagger
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

// Configure the HTTP request pipeline.
app.UseHttpsRedirection();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseAuthorization();
app.MapControllers();

app.Run();
EOF

cat > "${basepath}/${agentname}.Web.Endpoints/Program.cs" << EOF
using Microsoft.Extensions.FileProviders;

var builder = WebApplication.CreateBuilder(args);

builder.AddServiceDefaults();

var app = builder.Build();

// Add static files middleware for Assets/Files directory
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new PhysicalFileProvider(
        Path.Combine(Directory.GetCurrentDirectory(), "Assets", "Files")),
    RequestPath = "/Files"
});

app.MapGet("/", async (HttpContext httpContext) =>
{
    var contentPath = Path.Combine("Assets", $"index.html");
    if (!File.Exists(contentPath))
    {
        return Results.NotFound($"File not found: {contentPath}");
    }

    var content = await File.ReadAllTextAsync(contentPath);
    return Results.Content(content, "text/html");
});

app.Run();
EOF

# Create Assets directory and index.html for Web.Endpoints
mkdir -p "${basepath}/${agentname}.Web.Endpoints/Assets/Files"

# Create index.html
cat > "${basepath}/${agentname}.Web.Endpoints/Assets/index.html" << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AI Web Agents Template | BIZMASTER AGENCY</title>
    <!-- Material Design Icons -->
    <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
    <!-- Material Design Web Components -->
    <link href="https://fonts.googleapis.com/css?family=Roboto:300,400,500" rel="stylesheet">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
            font-family: 'Roboto', sans-serif;
        }
        
        body {
            background-color: #f5f5f5;
            color: #333;
            line-height: 1.6;
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 2rem;
        }
        
        .container {
            max-width: 800px;
            width: 100%;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.1);
            overflow: hidden;
            margin: 0 auto;
            transition: all 0.3s ease;
        }
        
        .header {
            background-color: #2196F3;
            color: white;
            padding: 2rem;
            text-align: center;
        }
        
        .header h1 {
            font-weight: 400;
            margin-bottom: 0.5rem;
            font-size: 2rem;
        }
        
        .header p {
            font-weight: 300;
            opacity: 0.9;
        }
        
        .content {
            padding: 2rem;
        }
        
        .feature {
            display: flex;
            align-items: center;
            margin-bottom: 1.5rem;
        }
        
        .feature-icon {
            background-color: #2196F3;
            color: white;
            width: 50px;
            height: 50px;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            margin-right: 1rem;
            flex-shrink: 0;
            font-size: 1.8rem; /* Increased font size for emojis */
        }
        
        .feature-text h3 {
            font-weight: 500;
            margin-bottom: 0.3rem;
            color: #1976D2;
        }
        
        .footer {
            background-color: #f9f9f9;
            padding: 1.5rem 2rem;
            text-align: center;
            border-top: 1px solid #eee;
        }
        
        .footer a {
            color: #2196F3;
            text-decoration: none;
            transition: color 0.3s;
        }
        
        .footer a:hover {
            color: #0D47A1;
            text-decoration: underline;
        }
        
        .cta-button {
            background-color: #2196F3;
            color: white;
            border: none;
            padding: 0.8rem 1.5rem;
            font-size: 1rem;
            border-radius: 4px;
            cursor: pointer;
            margin-top: 1.5rem;
            box-shadow: 0 2px 5px rgba(0, 0, 0, 0.1);
            transition: all 0.3s ease;
            display: inline-block;
            text-decoration: none;
        }
        
        .cta-button:hover {
            background-color: #1976D2;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
            transform: translateY(-2px);
        }
        
        /* Responsive design */
        @media (max-width: 768px) {
            .header {
                padding: 1.5rem;
            }
            
            .header h1 {
                font-size: 1.8rem;
            }
            
            .content {
                padding: 1.5rem;
            }
            
            .feature {
                flex-direction: column;
                text-align: center;
            }
            
            .feature-icon {
                margin-right: 0;
                margin-bottom: 1rem;
            }
        }
        
        @media (max-width: 480px) {
            body {
                padding: 1rem;
            }
            
            .header {
                padding: 1.2rem;
            }
            
            .header h1 {
                font-size: 1.5rem;
            }
            
            .content {
                padding: 1.2rem;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>AI Web Agents Starter Kit</h1>
            <p>A comprehensive framework for developing intelligent web agents</p>
        </div>
        
        <div class="content">
            <div class="feature">
                <div class="feature-icon">
                    <span>👨‍💻</span>
                </div>
                <div class="feature-text">
                    <h3>Developer-Friendly</h3>
                    <p>Build powerful AI web agents with our streamlined template designed for maximum productivity and efficiency.</p>
                </div>
            </div>
            
            <div class="feature">
                <div class="feature-icon">
                    <span>🤖</span>
                </div>
                <div class="feature-text">
                    <h3>AI-Powered</h3>
                    <p>Leverage cutting-edge artificial intelligence capabilities to create responsive and intelligent web agents.</p>
                </div>
            </div>
            
            <div class="feature">
                <div class="feature-icon">
                    <span>🔌</span>
                </div>
                <div class="feature-text">
                    <h3>Easy Integration</h3>
                    <p>Seamlessly integrate with existing systems using our well-designed API endpoints and Model Context Protocol.</p>
                </div>
            </div>
            
            <div style="text-align: center; margin-top: 2rem;">
                <a href="https://www.bizmaster.agency" class="cta-button">Learn More</a>
            </div>
        </div>
        
        <div class="footer">
            <p>Developed by <a href="https://www.bizmaster.agency" target="_blank">BIZMASTER AGENCY</a> &copy; 2025</p>
        </div>
    </div>
</body>
</html>
EOF

# Create sample DID file in Assets/Files
cat > "${basepath}/${agentname}.Web.Endpoints/Assets/Files/did.txt" << EOF
some did structure placed here
EOF

# Update Agent's Program.cs to properly register services
cat > "${basepath}/${agentname}.Agent/AppHost.cs" << EOF
var builder = DistributedApplication.CreateBuilder(args);

var apiService = builder.AddProject<Projects.${agentname}_Api_Endpoints>("api-endpoints");
var mcpService = builder.AddProject<Projects.${agentname}_Mcp_Endpoints>("mcp-endpoints");
var webService = builder.AddProject<Projects.${agentname}_Web_Endpoints>("web-endpoints");

builder.Build().Run();
EOF

# Create a README.md with documentation about the project structure
cat > "${basepath}/README.md" << EOF
# ${agentname} Project

This project was generated using the agent_starter_kit.sh script.

## Project Structure

- **${agentname}.Agent**: Aspire app host that coordinates all services
- **${agentname}.Agent.Cqrs**: Class library containing CQRS commands, queries, and handlers
- **${agentname}.Y.Core**: Aspire service defaults for configuration
- **${agentname}.Api.Endpoints**: Web API for external API endpoints
- **${agentname}.Mcp.Endpoints**: Web API for Model Context Protocol endpoints
- **${agentname}.Web.Endpoints**: Web application for UI

## Getting Started

1. Build the solution: \`dotnet build\`
2. Run the solution: \`dotnet run --project ${agentname}.Agent/${agentname}.Agent.csproj\`

## Dependencies

- .NET 9.0+
- .NET Aspire
- MediatR for CQRS
- FluentValidation
- Swashbuckle for OpenAPI/Swagger

EOF

# Add Healthchecks
add_packages "${basepath}/${agentname}.Api.Endpoints/${agentname}.Api.Endpoints.csproj" \
    "AspNetCore.HealthChecks.UI.Client"
add_packages "${basepath}/${agentname}.Mcp.Endpoints/${agentname}.Mcp.Endpoints.csproj" \
    "AspNetCore.HealthChecks.UI.Client"

# Restore, build, and watch
dotnet restore "${basepath}/${slnname}.sln"
dotnet build "${basepath}/${slnname}.sln"
dotnet watch run --project "${basepath}/${agentname}.Agent/${agentname}.Agent.csproj"

echo "All processes completed successfully."
echo "Project structure has been set up with CQRS pattern, example controllers, and MediatR integration."
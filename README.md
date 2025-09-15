# Secure AI Agents Development Starter Kit

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform](https://img.shields.io/badge/platform-.NET%209-brightgreen)](https://dotnet.microsoft.com/download)
[![C## 💳 Support Our## 💳 Support Our Security Research

**[🔗 Donate via Monobank →](https://send.monobank.ua/4yPJS8ta1c)**

Your support helps us continue research in the field of secure AI usage and development of ethical methodologies for artificial intelligence. Funds are directed towards:

- AI agent security research
- Development of new ethical standards
- Creation of open tools for the community
- Support for open source projects

## 📧 Contacts

If you have questions about using this starter kit, please create an issue in this repository.

---

**Made with ❤️ in Ukraine**

**[🔗 Donate via Monobank →](https://send.monobank.ua/4yPJS8ta1c)**

Your support helps us continue research in the field of secure AI usage and development of ethical methodologies for artificial intelligence. Funds are directed towards:

- AI agent security research
- Development of new ethical standards
- Creation of open tools for the community
- Support for open source projects

## 📧 Contacts

If you have questions about using this starter kit, please create an issue in this repository.

---

**Made with ❤️ in Ukraine**hields.io/badge/architecture-CQRS-orange)](https://docs.microsoft.com/en-us/azure/architecture/patterns/cqrs)

A starter kit for developing secure AI agents with built-in ethical methodology and CQRS architecture for easy integration with existing systems.

## 📑 Description

This starter kit provides basic infrastructure and architecture for creating AI agents that meet security and ethics standards. Using the CQRS (Command Query Responsibility Segregation) pattern and integration with Model Context Protocol (MCP), developers get a ready-made framework for fast and efficient deployment of AI solutions.

## 🔑 Key Features

- **Microservices Architecture** - built on .NET Aspire for service orchestration
- **CQRS Pattern** - clear separation of read and write operations
- **Model Context Protocol (MCP) Integration** - standardized protocol for interaction with large language models
- **Ethical Methodology** - built-in mechanisms for ensuring responsible AI interactions
- **API-First Approach** - full support for RESTful API and documentation through Swagger
- **Centralized Configuration** - single source of settings for all components
- **Ready-to-Use Endpoints** - pre-configured API, MCP, and web endpoints
- **AI Agent Documentation** - specialized documentation in AGENTS.md and agent_actions/ for development automation
- **Templates and Patterns** - ready-to-use templates for CQRS, controllers, and data layer

## 🛠️ Tech Stack

- **Platform:** .NET 9.0+
- **Orchestration:** .NET Aspire
- **CQRS:** MediatR
- **Validation:** FluentValidation
- **API Documentation:** Swagger/OpenAPI
- **Health Monitoring:** AspNetCore.HealthChecks
- **Development Templates:** Built-in templates and patterns for rapid development
- **Multi-Storage Data Support:** MongoDB, In-Memory Cache, JSON File Storage

## ⚙️ Requirements

- .NET 9.0 SDK or higher
- .NET Aspire Workload
- Bash-compatible terminal (for generation script)

## 🚀 Getting Started

### Step 1: Environment Setup

```bash
# Install .NET Aspire workload
dotnet workload install aspire
```

### Step 2: Clone Repository

```bash
# Clone starter kit
git clone https://github.com/tohoff82/ag-starter.git
cd ag-starter
```

### Step 3: Script Configuration

The `agent_starter_kit.sh` script uses the following syntax:

```bash
./agent_starter_kit.sh <agent-name>
```

**Parameters:**
- `<agent-name>` - your project name (required parameter)

**Examples:**
```bash
./agent_starter_kit.sh MyAgent       # Creates MyAgent project
./agent_starter_kit.sh ChatBot       # Creates ChatBot project  
./agent_starter_kit.sh DataProcessor # Creates DataProcessor project
```

**Note:** The script automatically:
- Checks for .NET 9.0+ availability
- Installs .NET Aspire templates (if needed)
- Creates all necessary projects and dependencies
- Generates AGENTS.md documentation and agent_actions/
- Sets up centralized configuration

### Step 4: Project Generation

```bash
# Run generation script with project name
chmod +x agent_starter_kit.sh
./agent_starter_kit.sh YourProjectName
```

**Note:** Replace `YourProjectName` with your project name (e.g., `MyAgent`, `ChatBot`, `DataProcessor`)

## 🚀 Quick Start

```bash
# Clone repository
git clone https://github.com/tohoff82/ag-starter.git
cd ag-starter

# Install .NET Aspire workload (if not already installed)
dotnet workload install aspire

# Generate new project
chmod +x agent_starter_kit.sh
./agent_starter_kit.sh MyAgent

# Run generated project
dotnet watch run --project MyAgent.Agent/MyAgent.Agent.csproj
```

## 📂 Generated Project Structure

After running the script, the following project structure will be created:

```
yourprojectname.Agent/            # Aspire host for orchestrating all services
yourprojectname.Agent.Cqrs/       # Class library for CQRS commands, queries & handlers
yourprojectname.Agent.Data/       # Data access layer with MongoDB, Cache, JSON support
yourprojectname.Y.Core/           # Core services and extensions
yourprojectname.Api.Endpoints/    # Web API for external API endpoints
yourprojectname.Mcp.Endpoints/    # Web API for Model Context Protocol endpoints
yourprojectname.Web.Endpoints/    # Web application for user interface
AGENTS.md                         # Documentation for AI agents
agent_actions/                    # Detailed development guides
├── AGENT_ACTION_CHOR.md          # Chain of Responsibility pattern
├── AGENT_ACTION_CODESTYLE.md     # Code standards
├── AGENT_ACTION_CONTROLLER.md    # Controller templates
├── AGENT_ACTION_CQRS.md          # CQRS component generation
└── AGENT_ACTION_DATA.md          # Data layer operations
README.md                         # Project documentation
src.sln                          # Solution file
```

### Component Description

- **Agent** - Main component that coordinates interaction between different services
- **Agent.Cqrs** - Contains commands, queries, and handlers for implementing CQRS pattern
- **Agent.Data** - Universal data access layer with multiple storage support
- **Y.Core** - Contains service extensions and default configurations
- **Api.Endpoints** - Provides RESTful API for interaction with external systems
- **Mcp.Endpoints** - Implements interface for interaction with AI models through MCP protocol
- **Web.Endpoints** - Provides web interface for system interaction
- **AGENTS.md** - Central documentation for AI agents with architecture and principles description
- **agent_actions/** - Detailed guides and templates for development automation

## 🔍 Architectural Principles

### CQRS (Command Query Responsibility Segregation)
The architecture clearly separates read operations (queries) and write operations (commands), which improves scalability, performance, and system security.

```csharp
// Example command
public class ExampleCommand : IRequest<bool>
{
    public string Data { get; set; } = string.Empty;
}

// Example query
public class ExampleQuery : IRequest<string>
{
    public string Id { get; set; } = string.Empty;
}
```

### Multi-Storage Data Architecture
The project supports multiple storage types through a universal Repository Pattern:

- **MongoDB** - for persistent storage and complex queries
- **In-Memory Cache** - for fast access to frequently used data
- **JSON File Storage (Flash)** - for configurations and small datasets

### Chain of Responsibility Pattern
Built-in Chain of Responsibility pattern for processing requests through a series of handlers:

- Type-safe request/response handling
- Configurable timeout and validation
- Comprehensive logging and error handling
- Dependency injection integration

### Model Context Protocol (MCP)
Standardized protocol for interaction with large language models (LLM), providing:

- Secure interaction with various AI providers
- Ethical constraints and access control
- Logging and monitoring of interactions
- Content filtering and prompt processing

## 🤖 AI Agent Documentation

The project includes specialized documentation for automating development using AI agents:

### AGENTS.md
Central documentation containing:
- Description of agent roles and configurations
- Communication scheme between agents
- Development guidelines
- Code standards and best practices

### agent_actions/ directory
Detailed guides for specific development tasks:

- **AGENT_ACTION_CHOR.md** - Chain of Responsibility pattern implementation
- **AGENT_ACTION_CODESTYLE.md** - C# code standards and best practices
- **AGENT_ACTION_CONTROLLER.md** - Templates for creating CQRS controllers
- **AGENT_ACTION_CQRS.md** - CQRS component generation (commands, queries, handlers)
- **AGENT_ACTION_DATA.md** - Working with data layer and multiple storages

This documentation allows AI agents to:
- Understand project architecture
- Generate code according to standards
- Automate creation of new components
- Ensure development consistency

## 🛡️ Ethical Methodology

The starter kit implements a series of mechanisms to ensure ethical AI usage:

- **Input Data Validation** - FluentValidation for checking input requests
- **Access Control** - Restrictions on access to sensitive operations
- **Logging and Audit** - Tracking all interactions with AI systems
- **Limitations and Filtering** - Ability to set restrictions on AI usage

## 📊 Monitoring and Diagnostics

The project includes ready-to-use tools for monitoring and diagnostics:

- **Health Checks** - Service status verification
- **Swagger/OpenAPI** - Real-time API documentation
- **Centralized Logging** - Single source for logs

## 📝 Running Generated Project

```bash
# Navigate to generated directory
cd yourprojectname-directory

# Restore dependencies and build project
dotnet restore
dotnet build

# Run project (replace YourProjectName with your project name)
dotnet run --project YourProjectName.Agent/YourProjectName.Agent.csproj

# or use dotnet watch for automatic reload during development
dotnet watch run --project YourProjectName.Agent/YourProjectName.Agent.csproj
```

After startup, the project will be available at:
- **Aspire Dashboard:** `https://localhost:17040` (with authentication token)
- **API Endpoints:** `https://localhost:7xxx` (port generated automatically)  
- **MCP Endpoints:** `https://localhost:7xxx` (port generated automatically)
- **Web Endpoints:** `https://localhost:7xxx` (port generated automatically)

## 🔐 Security

The starter kit implements basic security mechanisms:

- HTTPS by default
- Request validation
- Authorization and authentication (ready for configuration)
- Secure error handling

## 📈 Project Extension

The project is easily extensible to include additional functionality:

1. **Adding new CQRS components** - use templates from `agent_actions/AGENT_ACTION_CQRS.md`
2. **Creating new controllers** - follow patterns from `agent_actions/AGENT_ACTION_CONTROLLER.md`
3. **Extending data layer** - add new entities and repositories according to `agent_actions/AGENT_ACTION_DATA.md`
4. **Implementing new patterns** - use Chain of Responsibility and other patterns from `agent_actions/AGENT_ACTION_CHOR.md`
5. **Following code standards** - follow guidelines from `agent_actions/AGENT_ACTION_CODESTYLE.md`

### Quick Development Start

Thanks to built-in documentation for AI agents, you can:

- Automatically generate new CQRS commands and queries
- Create controllers with proper error handling and logging
- Add new entities with support for all storage types
- Ensure code consistency according to project standards

## 📄 License

This project is licensed under the Apache License 2.0. See the [LICENSE](LICENSE) file for detailed information.

## 👥 Authors

- **tohoff82** - *Development and maintenance* - [GitHub](https://github.com/tohoff82)
---

**Made with ❤️ in Ukraine**

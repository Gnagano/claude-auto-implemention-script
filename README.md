# Claude Auto Implementation Script

## Description

`create_pr_from_endpoints.sh` is a bash script that automates the implementation of API endpoints by:

1. Reading endpoint specifications from a configuration file and Google Spreadsheet
2. Using Claude AI to analyze spreadsheet data and generate implementation specifications
3. Creating Git branches for each endpoint
4. Implementing complete backend code (controllers, services, repositories, tests)
5. Creating pull requests automatically
6. Rollback support

The script is designed for Firebase Functions projects and follows a structured approach to ensure consistent, high-quality implementations.

## Prerequisites

**Important**: The script works best when the BASE_BRANCH already contains:
- Domain objects and types
- Database schema (Prisma)
- Base unit test and integration test patterns

It's recommended to create domain objects and schema first before running this script.

Pls see these:

+ DomainObject: https://github.com/Gnagano/europe_chartered_bank_backend/pull/581
+ Unit test + integration test: https://github.com/Gnagano/europe_chartered_bank_backend/pull/583
+ Result: https://github.com/Gnagano/europe_chartered_bank_backend/pull/589

## Setup

### 1. Repository Configuration (.mcp.json)

Create a `.mcp.json` file in your repository root with MCP server configuration:

```json
{
  "mcpServers": {
    "google-sheets": {
      "command": "npx",
      "args": ["-y", "@google-cloud/functions-framework", "--target", "sheets"],
      "env": {
        "GOOGLE_APPLICATION_CREDENTIALS": "/path/to/service-account.json"
      }
    }
  }
}
```

### 2. Claude Settings (.claude/settings.local.json)
Currently claude is running without permissions (dangerous mode). But if you encountered, you may need

Create a `settings.local.json` file in your `.claude` directory (both {{root}}/ and functions/):

```json
{
  "permissions": {
    "allow": [
      "Write",
      "Bash"
    ]
  }
}
```

## How to Run

### 1. Create Endpoints Configuration File

Create a text file (e.g., `endpoints.txt`) following ecb-endpoints.txt format:

### 2. Modify ```BASE_BRANCH ```

### 3. Run the Script

```bash
./create_pr_from_endpoints.sh endpoints.txt
```

## Configuration Format

### Spreadsheet Requirements

The script reads spreadsheet columns by their header names (not column positions):
- **UseCase ID** column: Contains the UseCase ID (BE{XX}-{YYYY}-{ZZZZ}) - used for EXACT matching
- **Endpoint** column: Contains the REST API endpoint path
- **HTTP Method** column: Contains the HTTP method (GET, POST, PUT, DELETE, etc.)
- **UseCase** column: Contains the descriptive name
- **UseCase (Methods)** column: Contains the main method name
- **params** column: Contains parameters in code-style format (e.g., JSON or TypeScript)
- **Service** column: Contains service names
- **Service(Methods)** column: Contains service method names
- **IRepository** column: Contains repository interface names
- **Repository** column: Contains repository implementation names

Note: The script uses EXACT string matching for UseCase ID and aggregates ALL services/repositories across multiple rows with the same UseCase ID.

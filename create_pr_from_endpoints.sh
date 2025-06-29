#!/bin/bash
# create_pr_from_endpoints.sh
# Read endpoints from file, create PRs with specifications for each endpoint

# Base branch configuration - can be overridden by environment variable
BASE_BRANCH="${BASE_BRANCH:-feature/implement-BE14-0201-1101}"

# Colored message functions
print_info() {
    echo -e "\033[34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[32m[SUCCESS]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[ERROR]\033[0m $1"
}

print_warning() {
    echo -e "\033[33m[WARNING]\033[0m $1"
}


# Fixed configuration - single mode operation

# Simple tracking for results
SUCCESS_COUNT=0
FAILED_COUNT=0
declare -A PROCESSED_ENDPOINTS=()

# Simple related branch detection
find_related_branch() {
    local current_destination="$1"
    local parent_path=$(dirname "$current_destination")
    
    for usecase in "${!PROCESSED_ENDPOINTS[@]}"; do
        local usecase_dest="${PROCESSED_ENDPOINTS[$usecase]}"
        if [[ "$usecase_dest" == "$parent_path"/* ]] && [[ "$usecase_dest" != "$current_destination" ]]; then
            echo "feature/implement-$usecase"
            return
        fi
    done
    echo "$BASE_BRANCH"
}

# Validation functions removed - Claude handles validation directly

# Simple usage
usage() {
    echo "Usage: $0 <endpoints_file>"
    echo "Config: CONFIG:SPREADSHEET_NAME=name, CONFIG:WORKSHEET_NAME=name, CONFIG:REPO_PATH=path"
    echo "Format: usecase_id|destination_folder"
    echo "Example: BE14-0201-1201|vault/useCase/debit-cards/requests/replacement"
    echo "Requirements: .mcp.json in repo root, .mdc files in functions/.cursor/rules/general/"
    exit ${1:-0}
}

# Pattern detection functions removed - Claude will analyze patterns from spreadsheet data

# Pattern analysis function removed - Claude will analyze from context

# Post-implementation review function removed - Claude handles quality checks

# Parse command line arguments - simplified single mode
ENDPOINTS_FILE=""
if [ $# -eq 0 ]; then
    print_error "Missing required argument: endpoints_file"
    usage 1
elif [ $# -eq 1 ]; then
    case $1 in
        -h|--help)
            usage 0
            ;;
        -*)
            print_error "Unknown option: $1"
            usage 1
            ;;
        *)
            ENDPOINTS_FILE="$1"
            ;;
    esac
else
    print_error "Too many arguments. Usage: $0 <endpoints_file>"
    usage 1
fi

# Check if endpoints file was provided
if [ -z "$ENDPOINTS_FILE" ]; then
    print_error "Missing required argument: endpoints_file"
    usage 1
fi

# Check if endpoints file exists
if [ ! -f "$ENDPOINTS_FILE" ]; then
    print_error "Endpoints file not found: $ENDPOINTS_FILE"
    exit 1
fi

# Convert to absolute path to avoid issues when changing directories
ENDPOINTS_FILE=$(realpath "$ENDPOINTS_FILE")

# No need to check allowedTools.txt - each project has its own .mcp.json and settings.local.json

print_info "Reading configuration from: $ENDPOINTS_FILE"

# Initialize configuration variables
SPREADSHEET_NAME=""
WORKSHEET_NAME=""
REPO_PATH=""

# Read global configuration from endpoints file
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines and comments
    if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
        continue
    fi
    
    # Check for configuration lines
    if [[ "$line" =~ ^CONFIG: ]]; then
        # Extract configuration
        CONFIG_LINE="${line#CONFIG:}"
        CONFIG_KEY="${CONFIG_LINE%%=*}"
        CONFIG_VALUE="${CONFIG_LINE#*=}"
        
        case "$CONFIG_KEY" in
            SPREADSHEET_NAME)
                SPREADSHEET_NAME="$CONFIG_VALUE"
                print_info "Found spreadsheet name: $CONFIG_VALUE"
                ;;
            WORKSHEET_NAME)
                WORKSHEET_NAME="$CONFIG_VALUE"
                print_info "Found worksheet name: $CONFIG_VALUE"
                ;;
            REPO_PATH)
                REPO_PATH="$CONFIG_VALUE"
                print_info "Found repository path: $CONFIG_VALUE"
                ;;
        esac
    fi
done < "$ENDPOINTS_FILE"

# Validate global configuration
if [ -z "$SPREADSHEET_NAME" ]; then
    print_error "SPREADSHEET_NAME must be configured in endpoints file"
    exit 1
fi

if [ -z "$WORKSHEET_NAME" ]; then
    print_error "WORKSHEET_NAME must be configured in endpoints file"
    exit 1
fi

# MCP configuration will be loaded after changing to repository directory

# Change to repository directory if specified
if [ -n "$REPO_PATH" ]; then
    print_info "Changing to repository directory: $REPO_PATH"
    cd "$REPO_PATH" || {
        print_error "Failed to change to repository directory: $REPO_PATH"
        exit 1
    }
fi

# Check for .mcp.json in the repository
print_info "Checking for MCP configuration in repository..."
if [ -f ".mcp.json" ]; then
    print_info "Found .mcp.json in repository"
    
    # Load MCP configuration from .mcp.json
    print_info "Loading MCP configuration from .mcp.json..."
    
    # Test if MCP servers can be loaded successfully
    if command -v claude &> /dev/null; then
        # Wait a moment for MCP servers to initialize
        sleep 2
        
        # Verify MCP servers are available
        MCP_STATUS=$(claude mcp list 2>&1)
        if [ $? -eq 0 ]; then
            print_success "MCP configuration loaded successfully"
            if ! echo "$MCP_STATUS" | grep -q "No MCP servers configured"; then
                print_info "Available MCP servers:"
                echo "$MCP_STATUS"
            fi
        else
            print_error "Failed to load MCP configuration from .mcp.json"
            print_error "Error: $MCP_STATUS"
            exit 1
        fi
    else
        print_warning "Claude CLI not found in PATH"
        print_info "Continuing anyway as MCP might be loaded at runtime..."
    fi
else
    print_error ".mcp.json not found in repository: $(pwd)"
    print_error "Please ensure .mcp.json exists in the repository root directory"
    print_info "The .mcp.json file should contain the MCP server configuration for this project"
    exit 1
fi

# Display global configuration summary
print_info "========================================="
print_info "Global Configuration:"
print_info "  Endpoints File: $ENDPOINTS_FILE"
print_info "  Spreadsheet Name: $SPREADSHEET_NAME"
print_info "  Worksheet Name: $WORKSHEET_NAME"
if [ -n "$REPO_PATH" ]; then
    print_info "  Repository Path: $REPO_PATH"
fi
print_info "========================================="

# Spreadsheet reading guidelines
SPREADSHEET_READING_RULES=$(cat << 'RULES_EOF'
CRITICAL SPREADSHEET READING RULES:

1. EXACT MATCHING REQUIREMENT:
   - Find rows where the "UseCase ID" column (Column K) EXACTLY equals the target value
   - Use EXACT string matching - no partial or fuzzy matches
   - For example: 'BE14-0301-2101' should NOT match 'BE01-0301-2101'
   - The match must be for the entire cell content

2. UseCase Grouping:
   - Group ALL rows that have the EXACT SAME UseCase ID
   - All rows sharing the same UseCase ID belong to the same use case definition
   - A single UseCase ID may span multiple consecutive rows

3. Extract Endpoint Information (from first row of the group):
   - "Endpoint" column (Column H): Contains the REST API endpoint path
   - "HTTP Method" column (Column G): Contains the HTTP method (GET, POST, PUT, DELETE, etc.)
   - These define the actual endpoint that will be implemented

4. Reading logic per UseCase ID group:
   - First row contains:
     • "UseCase": descriptive name
     • "UseCase (Methods)": main method name
     • "params": parameters in code-style format (e.g., JSON or TypeScript)
   - Subsequent rows may leave these columns blank or merged → treat as continuation

5. For each group, aggregate ALL services and repositories:
   - Collect ALL values from "Service" and "Service(Methods)" columns from ALL rows
   - Collect ALL values from "IRepository" and "Repository" columns from ALL rows
   - Each row may contain different services/repositories - collect them all
   - Ensure no duplicates when aggregating

6. Column header names (not positions) must be used to extract data:
   - Do not rely on fixed column letters (like A, B, C)
   - Match columns strictly based on their header name

7. Do not infer or guess beyond what the sheet provides:
   - No external logic should be assumed
   - If a value is blank and no previous context exists, skip it

EXAMPLE OUTPUT FOR BE14-0301-2101 (which spans multiple rows):
  usecase_id: BE14-0301-2101
  endpoint: /v1/debit-cards/requests/replacements/hyper/physical/payment
  http_method: POST
  usecase_name: DebitCardReplacementRequestHyperPhysicalPayReplacementFeeUseCase
  method: payReplacementFee
  params:
    - debitCardReplacementRequestId: string
    - user: User
  services:
    - DebitCardReplacementRequestHyperPhysicalQueryService.findPendingReplacementFeeById
    - DebitCardQueryService.findByGuaranteedOwner
    - BankAccountQueryService.findByIdByGuaranteedOwner
    - CustomerVerifiedQueryService.findCustomersVerifiedByBankAccount
    - DebitCardProductQueryService.guaranteeActiveById
    - BankWithdrawalCreateService.create
    - BankAccountUpdateService.updateBySpotTransaction
    - DebitCardReplacementRequestHyperPhysicalUpdateService.payIssuanceFee
    - DebitCardReplacementRequestBankTransactionCreateService.createFromTransaction
  repositories:
    - IDebitCardReplacementRequestHyperPhysicalRepository.findById
    - DebitCardReplacementRequestHyperPhysicalMySQLPrisma
    - IDebitCardRepository.findRawByIdWithUserIds
    - DebitCardMySQLPrisma
    - IBankAccountRepository.findById
    - BankAccountMySQLPrisma
    - [... and all other repositories from all rows]
RULES_EOF
)

# Function to generate common prompt parts
generate_common_prompt() {
    local usecase_id="$1"
    local base_branch="$2"
    local md_destination="$3"
    
    cat << 'EOF'
IMPORTANT: You are now in the repository directory: $(pwd)
PROJECT STRUCTURE: This is a Firebase Functions project. 

FIRST STEP: Change to the functions directory for all package manager commands:
cd functions

After changing to functions directory, you can run package manager commands directly.
NOTE: When in functions directory, file paths should be relative to functions (e.g., src/controller/... not functions/src/controller/...)
Track all operations for potential rollback. For each operation that creates or modifies something, log the rollback command.

CRITICAL: FOLLOW ALL .MDC GUIDELINES
Before starting ANY implementation:
1. Read and follow ALL .mdc files in functions/.cursor/rules/general/*.mdc
2. Create a checklist from the MDC rules to follow during implementation

This project uses Yarn as the primary package manager. Claude Code should follow a hybrid strategy for command execution:

Use Yarn for project-specific scripts:
- yarn test           # Use project's test configuration
- yarn build          # Use project's build scripts
- yarn lint           # Use project's linting setup

Use direct commands for speed and simplicity:
- npx prisma generate    # faster than yarn db:generate
- npx tsc --noEmit    # faster than yarn watch
- Prefer direct tool commands when Yarn introduces unnecessary overhead

MANDATORY QUALITY REQUIREMENTS (non-negotiable):
1. ZERO TypeScript compilation errors
2. ALL unit tests MUST pass
3. ALL integration tests MUST pass
4. Implementation must follow all .mdc guidelines
5. HTTP test files must be created and functional
6. If schema changes → generate schema by npx prisma generate
EOF
}

# Function removed - implementation steps now inline

# Count total endpoints first (for progress display)
TOTAL_ENDPOINTS=$(grep -E -v "^#|^CONFIG:|^$" "$ENDPOINTS_FILE" 2>/dev/null | wc -l)

# Process endpoints
print_info "Processing endpoints..."
print_info "Total endpoints to process: $TOTAL_ENDPOINTS"
ENDPOINT_COUNT=0
PROCESSED_COUNT=0
FAILED_COUNT=0

while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines, comments, and configuration lines
    if [ -z "$line" ] || [[ "$line" =~ ^# ]] || [[ "$line" =~ ^CONFIG: ]]; then
        continue
    fi
    
    # Parse usecase_id and destination
    if [[ "$line" =~ \| ]]; then
        usecase_id="${line%%|*}"
        md_destination="${line#*|}"
    else
        print_error "Invalid format for line: $line"
        print_error "Expected format: usecase_id|md_destination_folder"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi
    
    # Trim whitespace
    usecase_id=$(echo "$usecase_id" | xargs)
    md_destination=$(echo "$md_destination" | xargs)
    
    # Validate parsed values
    if [ -z "$usecase_id" ] || [ -z "$md_destination" ]; then
        print_error "Invalid usecase_id or destination in line: $line"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi
    
    ENDPOINT_COUNT=$((ENDPOINT_COUNT + 1))
    print_info "========================================="
    print_info "Processing UseCase $ENDPOINT_COUNT/$TOTAL_ENDPOINTS: $usecase_id"
    print_info "  Destination folder: $md_destination"
    
    # Find related branch for this endpoint
    CURRENT_BASE_BRANCH=$(find_related_branch "$md_destination")
    print_info "Base branch: $CURRENT_BASE_BRANCH"
    
    # Check for existing markdown
    md_hint=""
    MD_FILE_EXISTS=false
    if [ -d "$md_destination" ] && find "$md_destination" -name "*.md" -type f | grep -q .; then
        md_hint="(existing markdown in $md_destination - use for implementation)"
        MD_FILE_EXISTS=true
    fi
    
    # Create optimized prompt with explicit implementation commands
    PROMPT=$(cat << EOF
USECASE ID: $usecase_id → $md_destination
SPREADSHEET: $SPREADSHEET_NAME/$WORKSHEET_NAME
BASE: $CURRENT_BASE_BRANCH

$SPREADSHEET_READING_RULES

TASK: Extract UseCase ID $usecase_id from spreadsheet using EXACT matching, create implementation plan as markdown, then implement

PHASE 1 - CREATE MARKDOWN IMPLEMENTATION PLAN:
1. Extract ALL rows where "UseCase ID" column (Column K) EXACTLY equals '$usecase_id'
   - CRITICAL: Use EXACT string matching - '$usecase_id' must match the entire cell content
   - DO NOT match partial strings (e.g., 'BE14-0301-2101' should NOT match 'BE01-0301-2101')
   - Find ALL rows with this exact UseCase ID (may span multiple consecutive rows)
2. Analyze the complete endpoint structure:
   - Extract the endpoint path from "Endpoint" column
   - Extract the HTTP method from "HTTP Method" column
   - Count total rows for this UseCase ID
   - List all services needed (from all rows)
   - Identify all repository methods
3. Create markdown file in $md_destination/ with implementation plan:
   - First ensure directory exists: mkdir -p $md_destination
   - Filename: $md_destination/${usecase_id}.md
   - Include all extracted data from spreadsheet
   - Define implementation structure based on .mdc guidelines
   - List all components to be created
   - Include validation and testing requirements
   - The markdown should serve as a complete blueprint for implementation

PHASE 2 - IMPLEMENT BASED ON MARKDOWN PLAN:
1. cd functions
2. Read ALL .mdc rules from .cursor/rules/general/*.mdc
3. Read the markdown file you just created
4. Create branch: feature/implement-$usecase_id from $CURRENT_BASE_BRANCH
5. Implement based on markdown plan and .mdc guidelines:
   - Let .mdc rules guide what files to create
   - May include: types, helpers, validators, domain objects, etc.
   - Ensure ALL services from ALL rows are implemented
   - Create all necessary components as determined by .mdc rules
   - Update api.ts appropriately with the endpoint path from spreadsheet
   - Create comprehensive tests per .mdc guidelines
6. Validate: npx tsc --noEmit && yarn test
7. Commit and create PR

IMPLEMENTATION REQUIREMENTS:
• First create markdown plan, then implement based on that plan
• Follow ALL .mdc guidelines - they determine file structure
• Implement ALL services and repositories found across ALL rows with the same UseCase ID
• Use the exact endpoint path and HTTP method from the spreadsheet
• Each row may contain different services - implement them ALL
• Don't add operations not in spreadsheet
• Zero TS errors, all tests pass
• Use Write/MultiEdit tools

Think smart, plan thoroughly, implement completely, report briefly.
EOF
)

    # Check if confirmation is required for this usecase
    if [ "$CONFIRM_EACH_ENDPOINT" = true ]; then
        if ! ask_confirmation "Process UseCase $usecase_id?"; then
            print_info "Skipping UseCase: $usecase_id"
            continue
        fi
    fi
    
    # Check if markdown file already exists
    MD_FILE_EXISTS=false
    if [ -d "$md_destination" ]; then
        # Look for any .md files in the destination directory
        if find "$md_destination" -name "*.md" -type f | grep -q .; then
            MD_FILE_EXISTS=true
            existing_md_files=$(find "$md_destination" -name "*.md" -type f)
            print_warning "Found existing markdown files in $md_destination:"
            echo "$existing_md_files"
        fi
    fi
    
    # If markdown file exists, automatically implement code based on existing markdown
    if [ "$MD_FILE_EXISTS" = true ]; then
        echo ""
        print_info "========================================="
        print_info "EXISTING MARKDOWN FOUND FOR USECASE: $usecase_id"
        print_info "Destination: $md_destination"
        print_info "========================================="
        print_info "Will implement code based on existing markdown file..."
        # Modify prompt to use existing markdown instead of creating new one
        # First generate the common prompt content
        COMMON_PROMPT=$(generate_common_prompt "$usecase_id" "$CURRENT_BASE_BRANCH" "$md_destination")
        
        PROMPT="Please perform the following tasks for UseCase ID: $usecase_id

$COMMON_PROMPT

EXISTING MARKDOWN FILE FOUND: There is already a markdown file in $md_destination/

1. Read the existing markdown file(s) in $md_destination/ directory
2. MANDATORY: Also read ALL .mdc files in functions/.cursor/rules/general/*.mdc
3. Use the instructions from the existing markdown to implement the code
4. Follow all implementation requirements specified in the existing markdown
5. Ensure implementation follows all MDC guidelines

6. Create a new Git branch:
   - First, checkout the base branch: $CURRENT_BASE_BRANCH
   - Create new branch from it: 'feature/implement-$usecase_id'
   - Track branch creation for rollback: git branch -D feature/implement-$usecase_id

7. IMPLEMENT THE CODE LOCALLY based on existing markdown instructions:

   Implementation approach (implement first, test later):
   
   A. First, implement the domain objects and types:
      - Create necessary interfaces and types
   
   B. Implement core components as specified in the existing markdown:
      1. Use Case in src/useCase/\${pathOfUseCase}.ts
      2. Service functions in src/service/\${pathOfService}.ts
      3. Repository functions in src/repository/\${pathOfRepository}.ts
      4. Controller in src/controller/\${pathOfController}.ts
      5. Update src/api.ts to map endpoint base path to the new controller (prefer MultiEdit tool to avoid backup files)
      6. HTTP test file in rest/\${pathOfEndpoint}/\${HTTP_METHOD}_\${endpoint_description}.http
      7. Unit tests for ALL components:
         - Create unit tests in __tests__ directory or alongside source files
         - Test files should be named: *.test.ts or *.spec.ts
         - Write tests for useCase, service, repository
         - Follow unit-test-guideline.mdc if exists
         - Ensure all tests pass before proceeding
      8. Integration tests for controller:
         - Create integration test: [controller]/__tests__/[controller].integration.test.ts
         - Test all endpoints with authentication, error handling, response formats
         - Follow patterns defined in controller-integration-test-pattern.mdc guidelines
   
   C. MANDATORY: After ALL implementation is complete, validate and test:
      1. If you modified prisma/schema.prisma, run: npx prisma generate
      2. Test HTTP endpoints using the created .http files
      3. Ensure all unit tests pass: yarn test
      4. Ensure all integration tests pass: yarn test *.integration.test.ts
      5. FINAL STEP: Ensure NO TypeScript compilation errors: npx tsc --noEmit
   
   D. Ensure the implementation handles all edge cases, validations, and error scenarios

8. After successful local implementation and testing:
   - Clean up any backup files: rm -f src/api.ts.backup
   - Stage all implemented files: git add .
   - Commit all files changed with descriptive message
   - Track commit for rollback: git reset --hard HEAD~1

9. Push the implemented code to remote origin:
   - Push branch: git push origin feature/implement-$usecase_id
   - Track push for rollback: git push origin --delete feature/implement-$usecase_id

10. Create a pull request targeting the $CURRENT_BASE_BRANCH branch:
    - Title: '[Backend]$usecase_id \${httpMethod} \${endpoint} \${useCaseName} - IMPLEMENTED'
    - Body should include implementation summary
    - Track PR creation for rollback (save PR number and URL)
    - Use the exact HTTP method and endpoint path extracted from the spreadsheet

Replace all \${...} placeholders with actual values from the existing markdown file."
    fi
    
    # Execute Claude - optimized
    print_info "Processing: $usecase_id"
    
    if claude --print --dangerously-skip-permissions "$PROMPT"; then
        print_success "✓ $usecase_id"
        PROCESSED_ENDPOINTS["$usecase_id"]="$md_destination"
        ((SUCCESS_COUNT++))
    else
        print_error "✗ $usecase_id failed"
        print_info "Cleanup: git reset --hard HEAD~1; git branch -D feature/implement-$usecase_id 2>/dev/null"
        ((FAILED_COUNT++))
    fi
    
    # Brief pause
    sleep 1
    
done < "$ENDPOINTS_FILE"

# Summary
print_info "======================================="
print_info "SUMMARY: $SUCCESS_COUNT completed, $FAILED_COUNT failed"
[ $SUCCESS_COUNT -gt 0 ] && print_success "Successfully processed $SUCCESS_COUNT endpoints"
[ $FAILED_COUNT -gt 0 ] && print_error "$FAILED_COUNT endpoints failed - check logs"

# Show processed endpoints
if [ ${#PROCESSED_ENDPOINTS[@]} -gt 0 ]; then
    print_info "Processed endpoints:"
    for endpoint in "${!PROCESSED_ENDPOINTS[@]}"; do
        print_info "  ✓ $endpoint → ${PROCESSED_ENDPOINTS[$endpoint]}"
    done
fi

exit $FAILED_COUNT
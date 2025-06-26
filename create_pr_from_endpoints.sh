#!/bin/bash
# create_pr_from_endpoints.sh
# Read endpoints from file, create PRs with specifications for each endpoint

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


# Default values
AUTO_ROLLBACK=true
CONFIRM_EACH_ENDPOINT=false
DRY_RUN=false
ROLLBACK_ALL_ON_ANY_FAILURE=false
ROLLBACK_ALL_AT_END=false
USE_CACHE=true
FORCE_REFRESH_CACHE=false
CACHE_DIR="${CACHE_DIR:-/tmp/claude_pr_cache}"

# Function to show progress dots every 10 seconds
show_progress() {
    local pid=$1
    local message=$2
    local dots=""
    local elapsed=0
    
    # Print initial message to stderr (unbuffered)
    echo -n "$message" >&2
    
    while kill -0 $pid 2>/dev/null; do
        # Print dot to stderr to avoid buffering
        echo -n "." >&2
        dots="${dots}."
        elapsed=$((elapsed + 10))
        
        # Show elapsed time every 30 seconds
        if [ $((elapsed % 30)) -eq 0 ]; then
            echo -n " [${elapsed}s]" >&2
        fi
        
        # Clear line and restart dots after 12 dots (2 minutes)
        if [ ${#dots} -eq 12 ]; then
            echo -ne "\r\033[K$message" >&2
            dots=""
        fi
        
        sleep 10
    done
    
    echo " Done! [Total: ${elapsed}s]" >&2
}

# Rollback tracking arrays
declare -a ROLLBACK_OPERATIONS=()
declare -a ROLLBACK_DESCRIPTIONS=()

# Global rollback tracking (for all endpoints)
declare -a ALL_SUCCESSFUL_ENDPOINTS=()
declare -a ALL_ROLLBACK_OPERATIONS=()
declare -a ALL_ROLLBACK_DESCRIPTIONS=()

# Track processed endpoints and their PRs for related branching
declare -A PROCESSED_ENDPOINTS_TO_PR=()

# Function to add rollback operation
add_rollback() {
    local operation="$1"
    local description="$2"
    ROLLBACK_OPERATIONS+=("$operation")
    ROLLBACK_DESCRIPTIONS+=("$description")
    print_info "Added rollback: $description"
}

# Function to execute rollback operations
execute_rollback() {
    local endpoint_id="$1"
    print_warning "Executing rollback for endpoint: $endpoint_id"
    
    # Execute rollback operations in reverse order
    for ((i=${#ROLLBACK_OPERATIONS[@]}-1; i>=0; i--)); do
        local operation="${ROLLBACK_OPERATIONS[i]}"
        local description="${ROLLBACK_DESCRIPTIONS[i]}"
        
        print_info "Rolling back: $description"
        if eval "$operation" 2>/dev/null; then
            print_success "Rollback successful: $description"
        else
            print_warning "Rollback failed: $description"
        fi
    done
    
    # Clear rollback arrays for next endpoint
    ROLLBACK_OPERATIONS=()
    ROLLBACK_DESCRIPTIONS=()
}

# Function to clear rollback tracking
clear_rollback() {
    ROLLBACK_OPERATIONS=()
    ROLLBACK_DESCRIPTIONS=()
}

# Function to save successful endpoint for potential global rollback
save_successful_endpoint() {
    local endpoint_id="$1"
    ALL_SUCCESSFUL_ENDPOINTS+=("$endpoint_id")
    
    # Save current rollback operations to global arrays
    for operation in "${ROLLBACK_OPERATIONS[@]}"; do
        ALL_ROLLBACK_OPERATIONS+=("$operation")
    done
    for description in "${ROLLBACK_DESCRIPTIONS[@]}"; do
        ALL_ROLLBACK_DESCRIPTIONS+=("$description")
    done
}

# Function to execute rollback for all successful endpoints
execute_rollback_all() {
    print_warning "Executing rollback for ALL successful endpoints..."
    print_info "This will undo changes for endpoints: ${ALL_SUCCESSFUL_ENDPOINTS[*]}"
    
    # Execute rollback operations in reverse order
    for ((i=${#ALL_ROLLBACK_OPERATIONS[@]}-1; i>=0; i--)); do
        local operation="${ALL_ROLLBACK_OPERATIONS[i]}"
        local description="${ALL_ROLLBACK_DESCRIPTIONS[i]}"
        
        print_info "Rolling back: $description"
        if eval "$operation" 2>/dev/null; then
            print_success "Rollback successful: $description"
        else
            print_warning "Rollback failed: $description"
        fi
    done
    
    # Clear arrays
    ALL_SUCCESSFUL_ENDPOINTS=()
    ALL_ROLLBACK_OPERATIONS=()
    ALL_ROLLBACK_DESCRIPTIONS=()
}

# Function to find related PR based on destination path
find_related_pr() {
    local current_destination="$1"
    local related_pr=""
    local related_branch=""
    
    # Extract the parent path (e.g., vault/useCase/debit-cards)
    local parent_path=$(dirname "$current_destination")
    
    print_info "Looking for related PRs in path: $parent_path"
    
    # Look through processed endpoints for related ones
    for endpoint in "${!PROCESSED_ENDPOINTS_TO_PR[@]}"; do
        local pr_info="${PROCESSED_ENDPOINTS_TO_PR[$endpoint]}"
        local pr_destination=$(echo "$pr_info" | cut -d'|' -f2)
        local pr_branch=$(echo "$pr_info" | cut -d'|' -f3)
        
        # Check if the PR is in the same parent directory
        if [[ "$pr_destination" == "$parent_path"/* ]] && [[ "$pr_destination" != "$current_destination" ]]; then
            related_pr="$endpoint"
            related_branch="$pr_branch"
            print_info "Found related PR: $related_pr (branch: $related_branch)"
            break
        fi
    done
    
    echo "$related_branch"
}

# Function to ask for confirmation
ask_confirmation() {
    local message="$1"
    local default="${2:-n}"
    
    if [ "$default" = "y" ]; then
        prompt="$message [Y/n]: "
    else
        prompt="$message [y/N]: "
    fi
    
    read -p "$prompt" response
    response=${response:-$default}
    
    case "$response" in
        [yY]|[yY][eE][sS]) return 0 ;;
        *) return 1 ;;
    esac
}

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS] <endpoints_file>"
    echo ""
    echo "ARGUMENTS:"
    echo "  endpoints_file    Path to endpoints configuration file (required)"
    echo ""
    echo "OPTIONS:"
    echo "  --no-rollback          Disable automatic rollback on failure"
    echo "  --confirm-each         Ask for confirmation before processing each endpoint"
    echo "  --dry-run             Show what would be done without executing"
    echo "  --rollback-all-on-failure  Rollback ALL successful endpoints if ANY endpoint fails"
    echo "  --rollback-all-at-end     Ask to rollback all endpoints at the end"
    echo "  --no-cache            Disable spreadsheet caching"
    echo "  --refresh-cache       Force refresh cached spreadsheet data"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "CONFIGURATION FILE FORMAT:"
    echo "  Global configuration:"
    echo "    CONFIG:SPREADSHEET_NAME=<name>      # Google Sheets name"
    echo "    CONFIG:WORKSHEET_NAME=<name>        # Worksheet to search"
    echo "    CONFIG:REPO_PATH=<path>             # Repository path"
    echo ""
    echo "  Endpoints with destinations:"
    echo "    <endpoint_id>|<md_destination_folder>"
    echo ""
    echo "EXAMPLE endpoints.txt:"
    echo "  CONFIG:SPREADSHEET_NAME=JCF REST API"
    echo "  CONFIG:WORKSHEET_NAME=UseCase"
    echo "  CONFIG:REPO_PATH=/path/to/repo"
    echo "  BE07-0201-12|functions/vault/useCase/loan/loanRequest"
    echo "  BE07-0202-01|functions/vault/useCase/loan/loanApproval"
    echo "  BE07-0301-01|functions/vault/useCase/credit/creditCheck"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  Note: Claude will use .mcp.json and settings.local.json from each project"
    echo ""
    echo "MCP CONFIGURATION:"
    echo "  The script expects a .mcp.json file in the repository root directory"
    echo "  This file should contain the MCP server configuration for the project"
    echo ""
    echo "PR TITLE FORMAT:"
    echo "  [Backend]{{endpointId}} {{restAPIMethod}} {{endpointPath}} {{useCaseName}}"
    echo ""
    echo "IMPLEMENTATION SCOPE:"
    echo "  The script reads from REST API spreadsheet and implements code locally:"
    echo "  - Use Case functions and methods"
    echo "  - Service layer functions and methods"
    echo "  - Repository layer functions and methods"  
    echo "  - Controller with authentication and routing"
    echo "  - HTTP test files for endpoint testing"
    echo "  - Unit tests for all components"
    echo "  - All components must pass 'yarn tsc --noEmit' without errors"
    echo "  - Creates PR only after successful local implementation and testing"
    echo ""
    echo "LOCAL IMPLEMENTATION WORKFLOW:"
    echo "  - First action: cd functions (change to functions directory)"
    echo "  - Read all coding guidelines from /functions/.cursor/rules/general/*.mdc"
    echo "  - Implementation approach:"
    echo "    1. Implement all components (use case, service, repository, controller)"
    echo "    2. Create HTTP test files"
    echo "    3. Run 'yarn tsc --noEmit' to check TypeScript errors"
    echo "    4. Create basic unit tests"
    echo "    5. Create HTTP endpoints with .http files"
    echo "  - Create PR only after implementation passes all checks"
    echo "  - Timeout: 2 hours maximum for implementation"
    echo ""
    echo "RELATED PR BRANCHING:"
    echo "  The script will automatically detect related PRs in the same directory"
    echo "  and create new branches from them instead of from main branch"
    echo ""
    echo "ROLLBACK SCENARIOS:"
    echo "  1. Individual endpoint failure: Rollback just that endpoint (default)"
    echo "  2. User rejection: Manual rollback after successful processing (with --confirm-each)"
    echo "  3. Global rollback on any failure: Rollback ALL if ANY fails (--rollback-all-on-failure)"
    echo "  4. Global rollback at end: Ask to rollback all at completion (--rollback-all-at-end)"
    echo ""
    echo "ROLLBACK TRACKING:"
    echo "  - Git operations: branches, commits, pushes"
    echo "  - File operations: file creation, directory creation"
    echo "  - GitHub operations: PR creation and comments"
    exit ${1:-0}
}

# Function to detect implementation pattern from endpoint path
detect_pattern_from_path() {
    local path="$1"
    
    if [[ "$path" =~ request ]]; then
        echo "request"
    elif [[ "$path" =~ (transaction|transfer|payment|withdrawal|deposit) ]]; then
        echo "transaction"
    elif [[ "$path" =~ (report|history|statement|analytics) ]]; then
        echo "query"
    elif [[ "$path" =~ (management|admin) ]]; then
        echo "management"
    else
        # Default to management (CRUD) pattern
        echo "management"
    fi
}

# Function to generate pattern-specific verification
generate_pattern_verification() {
    local pattern_type="$1"
    
    case "$pattern_type" in
        "request")
            cat << 'EOF'
REQUEST PATTERN VERIFICATION:
[ ] Create request endpoint (POST)
[ ] List requests endpoint (GET)
[ ] Get request by ID (GET /:id)
[ ] State change endpoints:
    [ ] Approve (POST /:id/approve)
    [ ] Reject (POST /:id/reject)
    [ ] Cancel (POST /:id/cancel)
    [ ] Withdraw (POST /:id/withdraw)
[ ] Email notifications for state changes
[ ] Audit trail for all actions
[ ] Proper state validation in domain
EOF
            ;;
        "transaction")
            cat << 'EOF'
TRANSACTION PATTERN VERIFICATION:
[ ] Create transaction (POST)
[ ] Get transaction (GET /:id)
[ ] List transactions with filters (GET)
[ ] Transaction status check
[ ] Reversal endpoint (if applicable)
[ ] Atomic database operations
[ ] Balance updates handled correctly
[ ] Transaction history maintained
EOF
            ;;
        "management")
            cat << 'EOF'
MANAGEMENT PATTERN VERIFICATION:
[ ] Create resource (POST)
[ ] List resources (GET)
[ ] Get resource by ID (GET /:id)
[ ] Update resource (PUT /:id)
[ ] Partial update (PATCH /:id)
[ ] Delete resource (DELETE /:id)
[ ] Bulk operations (if applicable)
[ ] Validation for all operations
[ ] Proper authorization checks
EOF
            ;;
        "query")
            cat << 'EOF'
QUERY PATTERN VERIFICATION:
[ ] List with pagination (GET)
[ ] Advanced filtering support
[ ] Sorting capabilities
[ ] Aggregation endpoints (if needed)
[ ] Export functionality (CSV/Excel)
[ ] Performance optimization
[ ] Proper indexing considered
EOF
            ;;
    esac
}

# Function to generate pattern detection and analysis prompt
generate_pattern_analysis() {
    local endpoint_id="$1"
    local endpoint_path="$2"
    local domain_path="$3"
    local pattern_type="$4"
    
    cat << EOF
PATTERN DETECTION AND ANALYSIS:

Detected Pattern Type: ${pattern_type^^}

1. Pattern-Specific Requirements:
EOF
    
    case "$pattern_type" in
        "request")
            cat << 'EOF'
   - This is a REQUEST pattern (workflow-based)
   - Look for state machine diagrams (.puml files)
   - Identify all state transitions
   - Find approval/rejection workflows
   - Check email notification requirements
   - Look for BaseRequest or AbstractRequest classes
EOF
            ;;
        "transaction")
            cat << 'EOF'
   - This is a TRANSACTION pattern
   - Look for transaction processing logic
   - Check balance calculation methods
   - Find reversal mechanisms
   - Identify fee structures
   - Look for BaseTransaction classes
EOF
            ;;
        "management")
            cat << 'EOF'
   - This is a MANAGEMENT pattern (CRUD)
   - Standard CRUD operations required
   - Check for bulk operations needs
   - Identify validation rules
   - Look for similar management endpoints
EOF
            ;;
        "query")
            cat << 'EOF'
   - This is a QUERY/REPORT pattern
   - Focus on filtering and pagination
   - Check for aggregation needs
   - Look for export requirements
   - Identify performance considerations
EOF
            ;;
    esac
    
    cat << 'EOF'

2. Find Similar Implementations:
   - Search for other endpoints with the same pattern
   - Look in parallel domains for reference
   - Study the most complete implementation

3. Base Class Detection:
   - Search for abstract classes or interfaces
   - Check inheritance patterns in the domain
   - Identify required method implementations

4. Related Endpoints:
   - List all endpoints that work together
   - Identify the complete feature set
   - Check for missing operations
EOF
}

# Function to perform post-implementation review
post_implementation_review() {
    local endpoint_id="$1"
    local pattern_type="$2"
    
    print_info "Performing post-implementation review for pattern: $pattern_type"
    
    # Pattern-specific checks
    case "$pattern_type" in
        "request")
            # Check for state transition endpoints
            if ! find src/controller -name "*${endpoint_id}*" -type f -exec grep -l "approve\|reject\|cancel" {} \; | grep -q .; then
                print_warning "No state transition endpoints found (approve/reject/cancel)"
            fi
            # Check for email service
            if ! find src/service -name "*Email*" -type f | grep -q .; then
                print_warning "No email service implementation found for state changes"
            fi
            ;;
        "transaction")
            # Check for transaction handling
            if ! grep -r "prisma.\$transaction" src/ | grep -q .; then
                print_warning "No Prisma transactions found - atomicity may be compromised"
            fi
            # Check for calculation helpers
            if ! grep -r "addByDecimal\|minusByDecimal" src/ | grep -q .; then
                print_warning "No calculation helpers used - decimal arithmetic may be incorrect"
            fi
            ;;
        "management")
            # Check for CRUD completeness
            local crud_count=$(find src/controller -name "*${endpoint_id}*" -type f -exec grep -c "router\.\(get\|post\|put\|delete\)" {} \; | paste -sd+ | bc 2>/dev/null || echo 0)
            if [ "$crud_count" -lt 4 ]; then
                print_warning "Only $crud_count CRUD endpoints found (expected at least 4)"
            fi
            ;;
        "query")
            # Check for pagination/filtering
            if ! grep -r "limit\|offset\|orderBy" src/ | grep -q .; then
                print_warning "No pagination or filtering logic found"
            fi
            ;;
    esac
    
    # Common checks
    if ! grep -r "extends" src/domain | grep -q .; then
        print_warning "No inheritance detected - domain object may not extend base class"
    fi
    
    if ! find rest/ -name "*${endpoint_id}*" -o -name "*http" | grep -q .; then
        print_warning "No HTTP test files found for endpoint"
    fi
    
    # Count endpoints implemented
    local endpoint_count=$(find src/controller -name "*" -type f -exec grep -c "router\." {} \; | paste -sd+ | bc 2>/dev/null || echo 0)
    print_info "Total endpoints implemented: $endpoint_count"
}

# Parse command line arguments
ENDPOINTS_FILE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-rollback)
            AUTO_ROLLBACK=false
            shift
            ;;
        --confirm-each)
            CONFIRM_EACH_ENDPOINT=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --rollback-all-on-failure)
            ROLLBACK_ALL_ON_ANY_FAILURE=true
            shift
            ;;
        --rollback-all-at-end)
            ROLLBACK_ALL_AT_END=true
            shift
            ;;
        --no-cache)
            USE_CACHE=false
            shift
            ;;
        --refresh-cache)
            FORCE_REFRESH_CACHE=true
            shift
            ;;
        -h|--help)
            usage 0
            ;;
        -*)
            print_error "Unknown option: $1"
            usage 1
            ;;
        *)
            if [ -z "$ENDPOINTS_FILE" ]; then
                ENDPOINTS_FILE="$1"
            else
                print_error "Too many arguments. Only one endpoints file is allowed"
                usage 1
            fi
            shift
            ;;
    esac
done

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

# Function to generate common prompt parts
generate_common_prompt() {
    local endpoint_id="$1"
    local base_branch="$2"
    local md_destination="$3"
    
    cat << 'EOF'
IMPORTANT: You are now in the repository directory: $(pwd)
PROJECT STRUCTURE: This is a Firebase Functions project. 

FIRST STEP: Change to the functions directory for all package manager commands:
cd functions

After changing to functions directory, you can run yarn/npm commands directly without 'cd functions &&' prefix.
NOTE: When in functions directory, file paths should be relative to functions (e.g., src/controller/... not functions/src/controller/...)
Track all operations for potential rollback. For each operation that creates or modifies something, log the rollback command.

CRITICAL: FOLLOW ALL .MDC GUIDELINES
Before starting ANY implementation:
1. Read and follow ALL .mdc files in functions/.cursor/rules/general/*.mdc
2. Create a checklist from the MDC rules to follow during implementation
EOF
}

# Function to generate implementation steps
generate_implementation_steps() {
    local endpoint_id="$1"
    local base_branch="$2"
    local existing_markdown="$3"
    
    cat << EOF

5. Create a new Git branch:
   - First, checkout the base branch: $base_branch
   - Create new branch from it: 'feature/implement-$endpoint_id'
   - Track branch creation for rollback: git branch -D feature/implement-$endpoint_id

6. IMPLEMENT THE CODE LOCALLY$([ "$existing_markdown" = "true" ] && echo " based on existing markdown instructions" || echo " (instead of creating PR first)"):

   $([ "$existing_markdown" = "false" ] && echo "IMPORTANT: You MUST read and follow ALL files in /functions/.cursor/rules/general/*.mdc before implementation.
   
   PATTERN-BASED IMPLEMENTATION:
   Based on the detected pattern from the endpoint path, ensure you implement:
   - Request patterns: All state transitions (approve, reject, cancel)
   - Transaction patterns: Atomic operations, balance updates
   - Management patterns: Full CRUD operations
   - Query patterns: Filtering, pagination, sorting

   ")Implementation approach (implement first, test later):
   
   A. First, implement the domain objects and types:
      - Create necessary interfaces and types
   
   B. Implement core components$([ "$existing_markdown" = "true" ] && echo " as specified in the existing markdown" || echo ""):
      1. Use Case in src/useCase/\${pathOfUseCase}.ts
      2. Service functions in src/service/\${pathOfService}.ts
      3. Repository functions in src/repository/\${pathOfRepository}.ts
      4. Controller in src/controller/\${pathOfController}.ts
      5. Update src/api.ts to map endpoint base path to the new controller (prefer MultiEdit tool to avoid backup files)
      6. HTTP test file in rest/\${pathOfEndpoint}/\${HTTP_METHOD}_\${endpoint_description}.http
      7. Unit tests following unit-test-guideline.mdc
   
   C. After ALL implementation is complete, validate and test:
      1. If you modified prisma/schema.prisma, run 'yarn db:generate' to generate correct current schema types
      2. Test HTTP endpoints using the created .http files
      3. Run unit tests to ensure they pass
      4. FINAL STEP: Run 'yarn tsc --noEmit' to check for TypeScript errors
         - If there are errors, fix them and re-run until no errors remain
         - Only run this ONCE after all files are implemented
   
   D. Ensure the implementation handles all edge cases, validations, and error scenarios

7. IMPLEMENTATION VERIFICATION (PATTERN-BASED):
   Before proceeding, verify ALL items based on the detected pattern:
   
   For REQUEST patterns:
   [ ] All state transition endpoints implemented (approve, reject, cancel)
   [ ] Email notifications configured for state changes
   [ ] State validation in domain object
   [ ] Audit trail for all actions
   
   For TRANSACTION patterns:
   [ ] Atomic database operations using transactions
   [ ] Balance calculations using calculation helpers
   [ ] Transaction history maintained
   [ ] Reversal logic implemented (if applicable)
   
   For MANAGEMENT patterns:
   [ ] Complete CRUD operations (GET, POST, PUT, DELETE)
   [ ] Proper validation for all operations
   [ ] Bulk operations (if applicable)
   
   For QUERY patterns:
   [ ] Pagination implemented
   [ ] Filtering capabilities added
   [ ] Sorting options available
   [ ] Performance optimized
   
   COMMON VERIFICATIONS:
   [ ] Domain object extends correct parent class
   [ ] All abstract methods implemented
   [ ] Repository queries actual data (no hardcoded values)
   [ ] Authentication properly configured
   [ ] TypeScript compilation passes (yarn tsc --noEmit)
   [ ] HTTP test files created for ALL endpoints
   [ ] Unit tests created and passing for all layers

8. After successful local implementation and testing:
   - Clean up any backup files: rm -f src/api.ts.backup
   - Stage all implemented files: git add .
   - Commit with descriptive message:
     feat: Implement \${NameOfUseCase} endpoint $endpoint_id
     
     - Added \${useCaseMethods} use case
     - Added \${serviceMethods} service functions  
     - Added \${repositoryMethods} repository functions
     - Added \${controllerName} controller
     - Updated src/api.ts with endpoint mapping
     - Added HTTP test file
     - Added unit tests for all layers
     - TypeScript checks passed, all tests implemented
   - Track commit for rollback: git reset --hard HEAD~1

9. Push the implemented code to remote origin:
   - Push branch: git push origin feature/implement-$endpoint_id
   - Track push for rollback: git push origin --delete feature/implement-$endpoint_id

10. Create a pull request targeting the develop branch (or current base branch):
   - Target branch: develop (or the base branch that was checked out)
   - Title: '[Backend]$endpoint_id \${restAPIMethod} \${endpointPath} \${useCaseName} - IMPLEMENTED'
   - Body should include:
     * Brief description of the use case
     * REST API Method: \${restAPIMethod}
     * Endpoint Path: \${endpointPath}
     * ✅ IMPLEMENTATION COMPLETED locally
     * Components implemented:
       - ✅ Use Case: \${useCaseMethods}
       - ✅ Service: \${serviceMethods}
       - ✅ Repository: \${repositoryMethods}
       - ✅ Controller: \${controllerName}
       - ✅ API Mapping: Updated src/api.ts
       - ✅ HTTP Test: \${HTTP_METHOD}_\${endpoint_description}.http
       - ✅ Unit tests: All layers tested
     * Testing status:
       - ✅ TypeScript compilation: PASSED
       - ✅ Unit tests: PASSED
       - ✅ HTTP endpoint tests: VERIFIED
     * Base branch: $base_branch
     * Ready for code review and merge
   - Track PR creation for rollback (save PR number and URL)

11. IMPORTANT: Save the PR information for future reference:
    - Endpoint ID: $endpoint_id
    - PR Branch: feature/implement-$endpoint_id
    - PR URL: [save the actual PR URL]
    - Destination: $md_destination

ROLLBACK LOGGING: At the end, print a summary of all rollback commands that would undo the operations:
- File operations (rm commands)
- Directory operations (rmdir commands)  
- Git operations (branch deletion, reset commands, remote deletion)
- PR operations (PR number for manual closure)

Please log progress at each step and report any errors encountered.
$([ "$existing_markdown" = "true" ] && echo "Replace all \${...} placeholders with actual values from the existing markdown file." || echo "Replace all \${...} placeholders with actual values from the spreadsheet.")

PROGRESS CHECKPOINTS (report after each):
1. ✓ Spreadsheet data extracted with endpoint path: [show path]
2. ✓ Pattern detected: [REQUEST/TRANSACTION/MANAGEMENT/QUERY]
3. ✓ Domain analysis complete
4. ✓ Base classes identified: [list them]
5. ✓ Related endpoints found: [list them]
6. ✓ MDC rules reviewed
7. ✓ Implementation started
8. ✓ All endpoints implemented: [list all created endpoints]
9. ✓ TypeScript compilation passed
10. ✓ PR created: [show URL]
EOF
}

# Create cache directory if needed
if [ "$USE_CACHE" = true ] && [ ! -d "$CACHE_DIR" ]; then
    print_info "Creating cache directory: $CACHE_DIR"
    mkdir -p "$CACHE_DIR"
fi

# Function to get cache file path for an endpoint
get_cache_file() {
    local endpoint_id="$1"
    local spreadsheet_hash=$(echo -n "${SPREADSHEET_NAME}_${WORKSHEET_NAME}" | md5sum | cut -d' ' -f1)
    echo "${CACHE_DIR}/${spreadsheet_hash}_${endpoint_id}.cache"
}

# Function to check if cache is valid (24 hours)
is_cache_valid() {
    local cache_file="$1"
    if [ ! -f "$cache_file" ]; then
        return 1
    fi
    
    local cache_age=$(($(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)))
    local max_age=$((24 * 60 * 60))  # 24 hours in seconds
    
    if [ "$cache_age" -lt "$max_age" ]; then
        return 0
    else
        return 1
    fi
}

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
    
    # Parse endpoint and destination
    if [[ "$line" =~ \| ]]; then
        endpoint_id="${line%%|*}"
        md_destination="${line#*|}"
    else
        print_error "Invalid format for line: $line"
        print_error "Expected format: endpoint_id|md_destination_folder"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi
    
    # Trim whitespace
    endpoint_id=$(echo "$endpoint_id" | xargs)
    md_destination=$(echo "$md_destination" | xargs)
    
    # Validate parsed values
    if [ -z "$endpoint_id" ] || [ -z "$md_destination" ]; then
        print_error "Invalid endpoint or destination in line: $line"
        FAILED_COUNT=$((FAILED_COUNT + 1))
        continue
    fi
    
    ENDPOINT_COUNT=$((ENDPOINT_COUNT + 1))
    print_info "========================================="
    print_info "Processing endpoint $ENDPOINT_COUNT/$TOTAL_ENDPOINTS: $endpoint_id"
    print_info "  Destination folder: $md_destination"
    
    # Find related PR if exists
    BASE_BRANCH=$(find_related_pr "$md_destination")
    if [ -z "$BASE_BRANCH" ]; then
        BASE_BRANCH="develop"
        print_info "No related PR found. Will branch from: $BASE_BRANCH"
    else
        print_info "Found related PR. Will branch from: $BASE_BRANCH"
    fi
    
    # Check cache for this endpoint
    CACHE_FILE=$(get_cache_file "$endpoint_id")
    USE_CACHED_DATA=false
    
    if [ "$USE_CACHE" = true ] && [ "$FORCE_REFRESH_CACHE" = false ] && is_cache_valid "$CACHE_FILE"; then
        print_info "Found valid cache for endpoint $endpoint_id"
        USE_CACHED_DATA=true
    else
        print_info "No valid cache found for endpoint $endpoint_id, will read from spreadsheet"
    fi
    
    # Create the prompt for this endpoint
    if [ "$USE_CACHED_DATA" = true ]; then
        # Use cached data prompt
        PROMPT="Please perform the following tasks for endpoint ID: $endpoint_id

$(generate_common_prompt "$endpoint_id" "$BASE_BRANCH" "$md_destination")

1. Read the cached spreadsheet data from file: $CACHE_FILE

2. The cache contains all details from the '$WORKSHEET_NAME' worksheet for endpoint '$endpoint_id'

3. Use the cached data which includes:"
    else
        # Original prompt with spreadsheet reading
        PROMPT="Please perform the following tasks for endpoint ID: $endpoint_id

$(generate_common_prompt "$endpoint_id" "$BASE_BRANCH" "$md_destination")

1. Read the Google Sheets spreadsheet named '$SPREADSHEET_NAME'

2. Search for endpoint ID '$endpoint_id' in the '$WORKSHEET_NAME' worksheet

3. Read ALL details from the rows found. IMPORTANT: Extract ALL of the following:"
    fi
    
    # Continue with common details
    PROMPT="${PROMPT}
   - REST API Method (GET, POST, PUT, DELETE, etc.)
   - Endpoint Path (e.g., /api/v1/users) - CRITICAL: Store this for pattern detection
   - Use Case Name and Methods
   - Parameters
   - Service functions and methods
   - Repository functions and methods
   - Authentication requirements
   - Request body schema
   - Response format
   - Required HTTP headers
   
   PATTERN-BASED EXTRACTION:
   After identifying the endpoint path, detect the implementation pattern:
   - If path contains 'request' → Extract state transitions, approval logic, email triggers
   - If path contains 'transaction/transfer/payment' → Extract balance logic, reversal rules, fees
   - If path contains 'report/history/statement' → Extract filter params, aggregations, export formats
   - Otherwise → Extract standard CRUD requirements
   
   CRITICAL EXTRACTIONS:
   - Domain object properties (ALL fields, not just basic ones)
   - Parent class/interface to extend (look for hints in spreadsheet)
   - Related endpoints (other operations on same resource)
   - Business rules and validations
   - State diagram references
   - Email notification requirements
   - Transaction requirements (if any)
"
    
    # Add cache saving instruction if reading from spreadsheet
    if [ "$USE_CACHED_DATA" = false ]; then
        PROMPT="${PROMPT}

3a. IMPORTANT: Save the extracted data to cache file: $CACHE_FILE
    Create a JSON or structured text file with all the extracted information for future use.
"
    fi
    
    # Continue with markdown creation
    PROMPT="${PROMPT}

3b. PATTERN DETECTION AND DOMAIN ANALYSIS (MANDATORY - DO NOT SKIP):
   
   IMPORTANT: After extracting the endpoint path from spreadsheet:
   1. Store the endpoint path in a variable for pattern detection
   2. Detect the pattern type:
      - If path contains 'request' → REQUEST pattern
      - If path contains 'transaction/transfer/payment' → TRANSACTION pattern  
      - If path contains 'report/history/statement' → QUERY pattern
      - Otherwise → MANAGEMENT (CRUD) pattern
   3. Report the detected pattern clearly
   
   Based on the detected pattern, perform domain analysis:
   
   1. Detect the implementation pattern from the endpoint path
   2. Search for existing implementations with the same pattern
   3. Find base classes to extend:
      - For 'request' patterns → Look for BaseRequest, AbstractRequest
      - For 'transaction' patterns → Look for BaseTransaction
      - For general patterns → Look for domain-specific base classes
   4. Identify ALL required operations based on the pattern
   5. Check for .puml diagrams in the domain folder
   6. List all related endpoints that work together

4. Create a markdown file with comprehensive instructions for Claude Code Action:
   - MANDATORY: The markdown MUST instruct to read ALL .mdc files in functions/.cursor/rules/general/*.mdc
   - Create the instruction file at: $md_destination/\${NameOfUseCase}UseCase.md
   - Ensure the directory exists before creating the file (track directory creation for rollback)
   - The markdown should contain clear instructions for AI to implement:
     * The complete use case with all methods (based on pattern analysis)
     * All service functions and methods mentioned in the spreadsheet
     * All repository functions and methods mentioned in the spreadsheet
     * Controller implementation WITH ALL CRUD/ACTION ENDPOINTS
     * HTTP test files for EACH endpoint
     * Parameter validations and types
     * Error handling
     * Domain hierarchy (which class to extend)
     * State transitions (if applicable)
     * Email notifications (if state changes exist)
     * Testing requirements: Must pass 'yarn tsc --noEmit' (fix all TypeScript errors) (run from functions directory)
   - Track file creation for rollback: rm $md_destination/\${NameOfUseCase}UseCase.md

$(generate_implementation_steps "$endpoint_id" "$BASE_BRANCH" "false")"

    # Check if confirmation is required for this endpoint
    if [ "$CONFIRM_EACH_ENDPOINT" = true ]; then
        if ! ask_confirmation "Process endpoint $endpoint_id?"; then
            print_info "Skipping endpoint: $endpoint_id"
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
        print_info "EXISTING MARKDOWN FOUND FOR ENDPOINT: $endpoint_id"
        print_info "Destination: $md_destination"
        print_info "========================================="
        print_info "Will implement code based on existing markdown file..."
        # Modify prompt to use existing markdown instead of creating new one
        PROMPT="Please perform the following tasks for endpoint ID: $endpoint_id

$(generate_common_prompt "$endpoint_id" "$BASE_BRANCH" "$md_destination")

EXISTING MARKDOWN FILE FOUND: There is already a markdown file in $md_destination/

1. Read the existing markdown file(s) in $md_destination/ directory
2. MANDATORY: Also read ALL .mdc files in functions/.cursor/rules/general/*.mdc
3. Use the instructions from the existing markdown to implement the code
4. Follow all implementation requirements specified in the existing markdown
5. Ensure implementation follows all MDC guidelines

6. Create a new Git branch:
   - First, checkout the base branch: $BASE_BRANCH
   - Create new branch from it: 'feature/implement-$endpoint_id'
   - Track branch creation for rollback: git branch -D feature/implement-$endpoint_id

$(generate_implementation_steps "$endpoint_id" "$BASE_BRANCH" "true")"
    fi
    
    # Clear rollback tracking for this endpoint
    clear_rollback
    
    # Execute Claude for this endpoint
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would execute Claude for endpoint: $endpoint_id"
        print_info "[DRY RUN] Command: claude -p \"[PROMPT]\""
        print_success "[DRY RUN] Would process endpoint: $endpoint_id"
        PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
    else
        print_info "Executing Claude for endpoint: $endpoint_id"
        
        # Show configuration summary
        print_info "Configuration:"
        print_info "  Auto Rollback: $AUTO_ROLLBACK"
        print_info "  Confirm Each: $CONFIRM_EACH_ENDPOINT"
        print_info "  Base Branch: $BASE_BRANCH"
        
        # Store current directory
        ORIGINAL_DIR=$(pwd)
        
        # Run Claude with direct output to terminal
        print_info "Starting Claude local implementation for endpoint: $endpoint_id"
        print_info "Timeout set to 2 hours for implementation and testing..."
        print_info "========================================="
        print_info "CLAUDE OUTPUT (REAL-TIME):"
        print_info "========================================="
        
        # Debug: Check if Claude is accessible
        print_info "Checking Claude accessibility..."
        if ! command -v claude &> /dev/null; then
            print_error "Claude command not found in PATH"
            exit 1
        fi
        
        # Debug: Show what will be executed
        print_info "About to execute Claude (will use .mcp.json and settings.local.json from project)"
        print_info "Prompt preview (first 200 chars): ${PROMPT:0:200}..."
        
        # Run Claude with timeout and direct output to terminal (real-time)
        CLAUDE_TIMEOUT=${CLAUDE_TIMEOUT:-7200}  # 2 hours for complex implementations
        print_info "Starting Claude local implementation for endpoint: $endpoint_id"
        print_info "Timeout set to 2 hours for implementation and testing..."
        print_info "Claude output will appear below in real-time:"
        echo ""
        
        # Run Claude directly to show real-time output
        timeout $CLAUDE_TIMEOUT claude -p "$PROMPT"
        CLAUDE_EXIT_CODE=$?
        
        echo ""
        print_info "Claude completed with exit code: $CLAUDE_EXIT_CODE"
        
        print_info "========================================="
        print_info "CLAUDE EXECUTION COMPLETED"
        print_info "========================================"
        
        if [ $CLAUDE_EXIT_CODE -eq 0 ]; then
            print_success "Successfully processed endpoint: $endpoint_id"
            PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
            
            # Ask user for PR URL since we can't capture it from direct output
            read -p "Please enter the PR URL (or press Enter to skip): " PR_URL
            if [ -z "$PR_URL" ]; then
                PR_URL="Manual entry required"
            fi
            
            # Store endpoint information for future related PRs
            PROCESSED_ENDPOINTS_TO_PR["$endpoint_id"]="$PR_URL|$md_destination|feature/implement-$endpoint_id"
            
            # Save successful endpoint for potential global rollback
            save_successful_endpoint "$endpoint_id"
            
            # Ask if user wants to keep the changes
            if [ "$CONFIRM_EACH_ENDPOINT" = true ]; then
                if ! ask_confirmation "Keep changes for endpoint $endpoint_id?" "y"; then
                    print_warning "User requested rollback for endpoint: $endpoint_id"
                    if [ "$AUTO_ROLLBACK" = true ]; then
                        execute_rollback "$endpoint_id"
                    else
                        print_info "Auto-rollback disabled. Manual cleanup may be required."
                    fi
                    FAILED_COUNT=$((FAILED_COUNT + 1))
                    PROCESSED_COUNT=$((PROCESSED_COUNT - 1))
                fi
            fi
        else
            print_error "Failed to process endpoint: $endpoint_id (exit code: $CLAUDE_EXIT_CODE)"
            FAILED_COUNT=$((FAILED_COUNT + 1))
            
            # Automatic rollback on failure for this endpoint
            if [ "$AUTO_ROLLBACK" = true ]; then
                print_warning "Attempting automatic rollback for failed endpoint..."
                execute_rollback "$endpoint_id"
            else
                print_warning "Auto-rollback disabled. Manual cleanup may be required."
                print_info "To enable auto-rollback, remove the --no-rollback flag"
            fi
            
            # Global rollback on any failure
            if [ "$ROLLBACK_ALL_ON_ANY_FAILURE" = true ] && [ ${#ALL_SUCCESSFUL_ENDPOINTS[@]} -gt 0 ]; then
                print_warning "ROLLBACK_ALL_ON_ANY_FAILURE is enabled!"
                print_warning "Rolling back ALL successful endpoints due to this failure..."
                execute_rollback_all
                print_warning "All previous successful endpoints have been rolled back"
                break
            fi
            
            # Ask if user wants to continue with next endpoint
            if [ "$CONFIRM_EACH_ENDPOINT" = true ]; then
                if ! ask_confirmation "Continue with next endpoint?" "y"; then
                    print_info "User requested to stop processing"
                    break
                fi
            fi
            
            print_warning "Continuing with next endpoint..."
        fi
    fi
    
    # Add a small delay between endpoints to avoid rate limiting
    print_info "Waiting before processing next endpoint..."
    sleep 2
    
done < "$ENDPOINTS_FILE"

# Final summary
print_info "========================================="
print_success "Processing completed!"
print_info "Total endpoints: $ENDPOINT_COUNT"
print_success "Successfully processed: $PROCESSED_COUNT"
if [ $FAILED_COUNT -gt 0 ]; then
    print_warning "Failed: $FAILED_COUNT"
fi

# Show processed endpoints and their PRs
if [ ${#PROCESSED_ENDPOINTS_TO_PR[@]} -gt 0 ]; then
    print_info ""
    print_info "Processed endpoints and their PRs:"
    for endpoint in "${!PROCESSED_ENDPOINTS_TO_PR[@]}"; do
        pr_info="${PROCESSED_ENDPOINTS_TO_PR[$endpoint]}"
        pr_url=$(echo "$pr_info" | cut -d'|' -f1)
        print_info "  $endpoint: $pr_url"
    done
fi

# Global rollback at end option
if [ "$ROLLBACK_ALL_AT_END" = true ] && [ ${#ALL_SUCCESSFUL_ENDPOINTS[@]} -gt 0 ]; then
    print_info ""
    print_info "Successfully processed endpoints: ${ALL_SUCCESSFUL_ENDPOINTS[*]}"
    if ask_confirmation "Do you want to rollback ALL successful endpoints?"; then
        print_warning "User requested global rollback..."
        execute_rollback_all
        print_success "All endpoints have been rolled back"
    else
        print_info "Keeping all successful endpoints"
    fi
fi

# Show configuration used
print_info ""
print_info "Configuration used:"
print_info "  Auto Rollback: $AUTO_ROLLBACK"
print_info "  Confirm Each: $CONFIRM_EACH_ENDPOINT"
print_info "  Dry Run: $DRY_RUN"
print_info "  Rollback All On Failure: $ROLLBACK_ALL_ON_ANY_FAILURE"
print_info "  Rollback All At End: $ROLLBACK_ALL_AT_END"
print_info "  Use Cache: $USE_CACHE"
print_info "  Cache Directory: $CACHE_DIR"

if [ "$DRY_RUN" = true ]; then
    print_info ""
    print_info "This was a dry run. No actual changes were made."
    print_info "Remove --dry-run flag to execute the operations."
fi

if [ $FAILED_COUNT -gt 0 ] && [ "$AUTO_ROLLBACK" = false ]; then
    print_warning ""
    print_warning "Some endpoints failed and auto-rollback was disabled."
    print_warning "Manual cleanup may be required for failed endpoints."
    print_warning "Check Git branches, created files, and PRs manually."
fi
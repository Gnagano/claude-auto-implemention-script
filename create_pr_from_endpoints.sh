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
ALLOWED_TOOLS_FILE="${ALLOWED_TOOLS_FILE:-/mnt/c/Users/admin/Documents/GitHub/kiaiGithub/allowedTools.txt}"
AUTO_ROLLBACK=true
CONFIRM_EACH_ENDPOINT=false
DRY_RUN=false
ROLLBACK_ALL_ON_ANY_FAILURE=false
ROLLBACK_ALL_AT_END=false

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
    echo "  BE07-0201-12|vault/useCase/loan/loanRequest"
    echo "  BE07-0202-01|vault/useCase/loan/loanApproval"
    echo "  BE07-0301-01|vault/useCase/credit/creditCheck"
    echo ""
    echo "ENVIRONMENT VARIABLES:"
    echo "  ALLOWED_TOOLS_FILE: Path to allowed tools file (default: /mnt/c/Users/admin/Documents/GitHub/kiaiGithub/allowedTools.txt)"
    echo ""
    echo "MCP CONFIGURATION:"
    echo "  The script expects a .mcp.json file in the repository root directory"
    echo "  This file should contain the MCP server configuration for the project"
    echo ""
    echo "PR TITLE FORMAT:"
    echo "  [Backend]{{endpointId}} {{restAPIMethod}} {{endpointPath}} {{useCaseName}}"
    echo ""
    echo "IMPLEMENTATION SCOPE:"
    echo "  The script reads from REST API spreadsheet and creates PRs with instructions to implement:"
    echo "  - Use Case functions and methods"
    echo "  - Service layer functions and methods"
    echo "  - Repository layer functions and methods"
    echo "  - All components must pass 'yarn watch' and 'yarn build' without errors"
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

# Check if allowedTools.txt exists
if [ ! -f "$ALLOWED_TOOLS_FILE" ]; then
    print_error "allowedTools.txt file not found: $ALLOWED_TOOLS_FILE"
    print_error "This file is required to specify which tools Claude can use"
    exit 1
fi

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

# Process endpoints
print_info "Processing endpoints..."
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
    print_info "Processing endpoint $ENDPOINT_COUNT: $endpoint_id"
    print_info "  Destination folder: $md_destination"
    
    # Find related PR if exists
    BASE_BRANCH=$(find_related_pr "$md_destination")
    if [ -z "$BASE_BRANCH" ]; then
        BASE_BRANCH="main"
        print_info "No related PR found. Will branch from: $BASE_BRANCH"
    else
        print_info "Found related PR. Will branch from: $BASE_BRANCH"
    fi
    
    # Create the prompt for this endpoint
    PROMPT="Please perform the following tasks for endpoint ID: $endpoint_id

IMPORTANT: You are now in the repository directory: $(pwd)
Track all operations for potential rollback. For each operation that creates or modifies something, log the rollback command.

1. Read the Google Sheets spreadsheet named '$SPREADSHEET_NAME'

2. Search for endpoint ID '$endpoint_id' in the '$WORKSHEET_NAME' worksheet

3. Read ALL details from the rows found. IMPORTANT: Extract ALL of the following:
   - REST API Method (GET, POST, PUT, DELETE, etc.)
   - Endpoint Path (e.g., /api/v1/users)
   - Use Case Name and Methods
   - Parameters
   - Service functions and methods
   - Repository functions and methods
   - Any other implementation details

4. Create a markdown file with comprehensive instructions for Claude Code Action:
   - MANDATORY: First, read ALL .mdc files in functions/.cursor/rules/*.mdc
   - Create the instruction file at: $md_destination/\${NameOfUseCase}UseCase.md
   - Ensure the directory exists before creating the file (track directory creation for rollback)
   - The markdown should contain clear instructions for AI to implement:
     * The complete use case with all methods
     * All service functions and methods mentioned in the spreadsheet
     * All repository functions and methods mentioned in the spreadsheet
     * Parameter validations and types
     * Error handling
     * Check and implement any missing domain objects mentioned in the spreadsheet
     * Testing requirements: Must pass 'yarn lint', 'yarn watch' and 'yarn build' without errors
   - Track file creation for rollback: rm $md_destination/\${NameOfUseCase}UseCase.md

5. Create a new Git branch:
   - First, checkout the base branch: $BASE_BRANCH
   - Create new branch from it: 'feature/implement-$endpoint_id'
   - Track branch creation for rollback: git branch -D feature/implement-$endpoint_id

6. Stage and commit the newly created markdown file with message:
   docs: Add full implementation spec for \${NameOfUseCase}
   
   Added comprehensive specification for implementing:
   - \${NameOfUseCase} use case
   - Related service functions
   - Related repository functions
   Based on endpoint $endpoint_id from the REST API spreadsheet.
   - Track commit for rollback: git reset --hard HEAD~1

7. Push the branch to remote origin
   - Track push for rollback: git push origin --delete feature/implement-$endpoint_id

8. Create a pull request with:
   - Title: '[Backend]$endpoint_id \${restAPIMethod} \${endpointPath} \${useCaseName}'
   - Body should include:
     * Brief description of the use case
     * REST API Method: \${restAPIMethod}
     * Endpoint Path: \${endpointPath}
     * Components to implement:
       - Use Case: \${useCaseMethods}
       - Service: \${serviceMethods}
       - Repository: \${repositoryMethods}
     * Base branch: $BASE_BRANCH
   - Track PR creation for rollback (save PR number and URL)

9. Add a comment to the PR:
   @claude

   Please implement the complete backend for \${NameOfUseCase}

   You can find the full specification in:
   /$md_destination/\${NameOfUseCase}UseCase.md

   IMPORTANT: You MUST read ALL files in /functions/.cursor/rules/*.mdc before implementation.
   Strictly follow all guidelines including domain object implementation.

   Please implement:
   1. Use Case in src/useCase/\${pathOfUseCase}.ts
   2. Service functions in src/service/\${pathOfService}.ts
   3. Repository functions in src/repository/\${pathOfRepository}.ts
   4. Any necessary interfaces, types, or domain models
   5. Unit tests for all components

   CRITICAL: After implementation, you MUST:
   1. Run 'yarn watch' to ensure no TypeScript errors
   2. Run 'yarn build' to ensure the build succeeds
   3. Fix any errors before marking the task as complete

   The implementation should handle all edge cases, validations, and error scenarios.

10. IMPORTANT: Save the PR information for future reference:
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
Replace all \${...} placeholders with actual values from the spreadsheet."

    # Check if confirmation is required for this endpoint
    if [ "$CONFIRM_EACH_ENDPOINT" = true ]; then
        if ! ask_confirmation "Process endpoint $endpoint_id?"; then
            print_info "Skipping endpoint: $endpoint_id"
            continue
        fi
    fi
    
    # Clear rollback tracking for this endpoint
    clear_rollback
    
    # Execute Claude for this endpoint
    if [ "$DRY_RUN" = true ]; then
        print_info "[DRY RUN] Would execute Claude for endpoint: $endpoint_id"
        print_info "[DRY RUN] Command: claude --allowedTools \"$(paste -sd, "$ALLOWED_TOOLS_FILE")\" -p \"[PROMPT]\""
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
        
        # Run Claude and capture output with progress indicator
        print_info "Starting Claude execution for endpoint: $endpoint_id"
        print_info "This may take several minutes..."
        
        # Create a temporary file for Claude output
        CLAUDE_OUTPUT=$(mktemp)
        
        # Run Claude in background to show progress
        claude --allowedTools "$(paste -sd, "$ALLOWED_TOOLS_FILE")" -p "$PROMPT" < /dev/null > "$CLAUDE_OUTPUT" 2>&1 &
        CLAUDE_PID=$!
        
        # Show progress while Claude processes the endpoint
        show_progress $CLAUDE_PID "Processing endpoint $endpoint_id"
        
        # Wait for Claude to complete and get exit code
        wait $CLAUDE_PID
        CLAUDE_EXIT_CODE=$?
        
        # Display Claude output
        print_info "Claude execution completed. Output:"
        echo "----------------------------------------"
        cat "$CLAUDE_OUTPUT"
        echo "----------------------------------------"
        
        # Try to extract PR URL from Claude's output
        PR_URL=$(grep -oE "https://github.com/[^/]+/[^/]+/pull/[0-9]+" "$CLAUDE_OUTPUT" | head -1)
        
        # Clean up temp file
        rm -f "$CLAUDE_OUTPUT"
        
        if [ $CLAUDE_EXIT_CODE -eq 0 ]; then
            print_success "Successfully processed endpoint: $endpoint_id"
            PROCESSED_COUNT=$((PROCESSED_COUNT + 1))
            
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
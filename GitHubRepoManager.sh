#!/bin/bash

# GitHub Repository Manager
# Comprehensive Git repository lifecycle management tool
#
# Features:
# - Create new GitHub repositories with local setup
# - Delete repositories from both GitHub and local filesystem  
# - Fix common git repository issues (ownership, tracking, conflicts)
# - Auto-commit and push multiple repositories in batch
# - Set up branch protection rules to prevent accidental changes
# - Manage pull requests (list, merge, close)
# - Cleanup repositories for GA release with backup
# - Restore repositories from backup archives
# - Support for GitHub.com and GitHub Enterprise
# - Comprehensive error handling and safety confirmations
# - Secure token-based authentication
# - Automatic git configuration setup
# - Unrelated histories and merge conflict resolution
# - Dry-run mode for batch operations
# - Auto-detection of template variables and README passwords for --no-verify commits
#
# Usage:
#   ./GitHubRepoManager.sh [--help] [--create] [--delete] [--fix] [--auto-commit] [--protect] [--manage-pr] [--ga-cleanup] [--restore]
#
# Requirements:
# - curl (for GitHub API calls)
# - git (for repository operations)
# - tar (for backup operations)
# - GitHub Personal Access Token with appropriate scopes:
#   - For creation: 'repo' scope
#   - For deletion: 'delete_repo' scope
#   - For auto-commit: 'repo' scope
#   - For protection: 'repo' scope with admin permissions
#   - For pull requests: 'repo' scope
#
# Author: GitHub Repository Manager v4.2.3
# Date: November 18, 2025

# reset

# set -eo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Back-compat helper (alias) - some paths call print_info
print_info() { print_status "$1"; }

# Function to check folders for git repositories
check_folders_for_git_repos() {
  echo ""
  print_status "Scanning for folders that are NOT git repositories..."
  local base_path
  read -p "Enter base path to scan (default: current directory): " base_path
  base_path="${base_path:-.}"

  if [[ ! -d "$base_path" ]]; then
    print_error "Directory not found: $base_path"
    return 1
  fi

  cd "$base_path" || return 1

  local non_git_folders=()
  for dir in */; do
    dir="${dir%/}"
    # Skip hidden folders
    [[ "$dir" =~ ^\..* ]] && continue
    # Skip if .git exists
    if [[ ! -d "$dir/.git" ]]; then
      non_git_folders+=("$dir")
    fi
  done

  if [[ ${#non_git_folders[@]} -eq 0 ]]; then
    print_success "All folders are git repositories."
    return 0
  fi

  echo ""
  print_status "Folders that are NOT git repositories:"
  local i=1
  for folder in "${non_git_folders[@]}"; do
    echo "$i) $folder"
    ((i++))
  done

  echo ""
  read -p "Enter the number(s) of the folder(s) to create as new GitHub repos (comma-separated, or 'all'): " selection

  if [[ "$selection" == "all" ]]; then
    selected_indices=($(seq 1 ${#non_git_folders[@]}))
  else
    IFS=',' read -ra selected_indices <<< "$selection"
  fi

  for idx in "${selected_indices[@]}"; do
    folder="${non_git_folders[$((idx-1))]}"
    if [[ -n "$folder" ]]; then
      echo ""
      print_status "Creating new GitHub repository for: $folder"
      # Use the full path automatically
      create_repository_with_path "$base_path/$folder"
    fi
  done
}

# Function to scan for local git repositories needing push
scan_and_push_git_repos() {
  echo ""
  print_status "Scanning for local git repositories that need to be pushed..."
  local base_path
  read -p "Enter base path to scan (default: current directory): " base_path
  base_path="${base_path:-.}"

  if [[ ! -d "$base_path" ]]; then
    print_error "Directory not found: $base_path"
    return 1
  fi

  cd "$base_path" || return 1

  local repos_needing_push=()
  local repos_with_changes=()
  local total_repos=0

  # Find all git repositories
  while IFS= read -r -d '' git_dir; do
    repo_path=$(dirname "$git_dir")
    repo_name=$(basename "$repo_path")
    ((total_repos++))
    
    cd "$repo_path" 2>/dev/null || continue
    
    # Check for uncommitted changes
    local has_uncommitted=false
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null || [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
      has_uncommitted=true
      repos_with_changes+=("$repo_path")
    fi
    
    # Check for unpushed commits
    local has_unpushed=false
    local remote_branch=""
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    
    if [[ -n "$current_branch" && "$current_branch" != "HEAD" ]]; then
      remote_branch=$(git rev-parse --abbrev-ref "$current_branch@{upstream}" 2>/dev/null || echo "")
      if [[ -n "$remote_branch" ]]; then
        local ahead_count=$(git rev-list --count "$remote_branch..$current_branch" 2>/dev/null || echo "0")
        if [[ "$ahead_count" -gt 0 ]]; then
          has_unpushed=true
        fi
      else
        # No upstream branch set, likely needs initial push
        if [[ $(git rev-list --count HEAD 2>/dev/null || echo "0") -gt 0 ]]; then
          has_unpushed=true
        fi
      fi
    fi
    
    if [[ "$has_uncommitted" == "true" || "$has_unpushed" == "true" ]]; then
      local status_info=""
      [[ "$has_uncommitted" == "true" ]] && status_info+="uncommitted changes"
      [[ "$has_uncommitted" == "true" && "$has_unpushed" == "true" ]] && status_info+=", "
      [[ "$has_unpushed" == "true" ]] && status_info+="unpushed commits"
      repos_needing_push+=("$repo_path|$status_info")
    fi
    
    cd "$base_path" || return 1
  done < <(find "$base_path" -name ".git" -type d -print0 2>/dev/null)

  print_status "Scan complete: Found $total_repos git repositories"
  
  if [[ ${#repos_needing_push[@]} -eq 0 ]]; then
    print_success "All git repositories are up to date!"
    return 0
  fi

  echo ""
  print_status "Repositories needing attention (${#repos_needing_push[@]} found):"
  local i=1
  for repo_info in "${repos_needing_push[@]}"; do
    IFS='|' read -r repo_path status_info <<< "$repo_info"
    repo_name=$(basename "$repo_path")
    echo "$i) $repo_name ($status_info)"
    echo "   Path: $repo_path"
    ((i++))
  done

  echo ""
  echo "Actions available:"
  echo "1) Auto-commit and push selected repositories"
  echo "2) Show detailed status for selected repositories"
  echo "3) Generate comprehensive report (needs update vs up-to-date)"
  echo "4) Return to main menu"
  echo ""
  read -p "Choose action (1-4): " action
  
  case $action in
    1)
      echo ""
      read -p "Enter repository numbers to commit and push (comma-separated, or 'all'): " selection
      
      if [[ "$selection" == "all" ]]; then
        selected_indices=($(seq 1 ${#repos_needing_push[@]}))
      else
        IFS=',' read -ra selected_indices <<< "$selection"
      fi
      
      read -p "Enter commit message for repositories with changes [Auto-commit from scan]: " commit_msg
      commit_msg=${commit_msg:-"Auto-commit from scan"}
      
      local success_count=0
      local failed_count=0
      
      for idx in "${selected_indices[@]}"; do
        repo_info="${repos_needing_push[$((idx-1))]}"
        if [[ -n "$repo_info" ]]; then
          IFS='|' read -r repo_path status_info <<< "$repo_info"
          repo_name=$(basename "$repo_path")
          
          echo ""
          print_status "Processing: $repo_name"
          cd "$repo_path" 2>/dev/null || continue
          
          # Handle uncommitted changes
          if [[ "$status_info" == *"uncommitted changes"* ]]; then
            print_status "Adding and committing changes..."
            if git add --all 2>/dev/null; then
              local commit_cmd="git commit -m \"$commit_msg\""
              if should_use_no_verify "$(pwd)"; then
                commit_cmd="git commit --no-verify -m \"$commit_msg\""
                print_status "Using --no-verify due to template variables or README passwords detected"
              fi
              
              if eval "$commit_cmd" 2>/dev/null; then
                print_success "Changes committed for: $repo_name"
              else
                print_error "Failed to commit changes for: $repo_name"
                ((failed_count++))
                continue
              fi
            else
              print_error "Failed to add files for: $repo_name"
              ((failed_count++))
              continue
            fi
          fi
          
          # Handle push
          if [[ "$status_info" == *"unpushed commits"* ]]; then
            print_status "Pushing commits..."
            if git push 2>/dev/null || git push --set-upstream origin $(git rev-parse --abbrev-ref HEAD) 2>/dev/null; then
              print_success "Successfully pushed: $repo_name"
              ((success_count++))
            else
              print_error "Failed to push: $repo_name"
              ((failed_count++))
            fi
          else
            ((success_count++))
          fi
        fi
      done
      
      echo ""
      print_status "Operation complete:"
      echo "  Successful: $success_count"
      echo "  Failed: $failed_count"
      ;;
      
    2)
      echo ""
      read -p "Enter repository numbers to show status (comma-separated, or 'all'): " selection
      
      if [[ "$selection" == "all" ]]; then
        selected_indices=($(seq 1 ${#repos_needing_push[@]}))
      else
        IFS=',' read -ra selected_indices <<< "$selection"
      fi
      
      for idx in "${selected_indices[@]}"; do
        repo_info="${repos_needing_push[$((idx-1))]}"
        if [[ -n "$repo_info" ]]; then
          IFS='|' read -r repo_path status_info <<< "$repo_info"
          repo_name=$(basename "$repo_path")
          
          echo ""
          echo "=========================================="
          print_status "Repository: $repo_name"
          echo "Path: $repo_path"
          echo "Status: $status_info"
          echo ""
          
          cd "$repo_path" || continue
          
          # Show git status
          echo "Git Status:"
          git status --short 2>/dev/null || echo "Could not get git status"
          
          # Show unpushed commits if any
          local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
          local remote_branch=$(git rev-parse --abbrev-ref "$current_branch@{upstream}" 2>/dev/null || echo "")
          if [[ -n "$remote_branch" ]]; then
            local ahead_count=$(git rev-list --count "$remote_branch..$current_branch" 2>/dev/null || echo "0")
            if [[ "$ahead_count" -gt 0 ]]; then
              echo ""
              echo "Unpushed commits ($ahead_count):"
              git log --oneline "$remote_branch..$current_branch" 2>/dev/null | head -5
              [[ "$ahead_count" -gt 5 ]] && echo "... and $((ahead_count - 5)) more commits"
            fi
          fi
          echo "=========================================="
        fi
      done
      ;;
      
    3)
      # Generate comprehensive report
      echo ""
      print_status "Generating Repository Status Report..."
      
      # Get current timestamp for report
      local report_timestamp=$(date "+%Y-%m-%d %H:%M:%S")
      local report_file="/tmp/git_repo_report_$(date +%Y%m%d_%H%M%S).txt"
      
      # Create report header
      cat > "$report_file" << EOF
========================================
Git Repository Status Report
Generated: $report_timestamp
Scan Path: $base_path
========================================

SUMMARY:
- Total repositories scanned: $total_repos
- Repositories needing updates: ${#repos_needing_push[@]}
- Repositories up-to-date: $((total_repos - ${#repos_needing_push[@]}))

EOF

      echo ""
      echo "Report Summary:"
      echo "- Total repositories scanned: $total_repos"
      echo "- Repositories needing updates: ${#repos_needing_push[@]}"
      echo "- Repositories up-to-date: $((total_repos - ${#repos_needing_push[@]}))"
      
      # Add repositories needing updates
      if [[ ${#repos_needing_push[@]} -gt 0 ]]; then
        cat >> "$report_file" << EOF

REPOSITORIES NEEDING UPDATES:
EOF
        
        echo ""
        print_status "Repositories needing updates:"
        
        for repo_info in "${repos_needing_push[@]}"; do
          IFS='|' read -r repo_path status_info <<< "$repo_info"
          repo_name=$(basename "$repo_path")
          
          echo "[NEEDS UPDATE] $repo_name - $status_info"
          echo "[NEEDS UPDATE] $repo_name - $status_info" >> "$report_file"
          echo "   Path: $repo_path" >> "$report_file"
          
          # Get more detailed info for report
          cd "$repo_path" || continue
          
          # Count uncommitted files
          local uncommitted_count=0
          if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null || [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
            uncommitted_count=$(git status --porcelain 2>/dev/null | wc -l)
          fi
          
          # Count unpushed commits
          local unpushed_count=0
          local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
          if [[ -n "$current_branch" && "$current_branch" != "HEAD" ]]; then
            local remote_branch=$(git rev-parse --abbrev-ref "$current_branch@{upstream}" 2>/dev/null || echo "")
            if [[ -n "$remote_branch" ]]; then
              unpushed_count=$(git rev-list --count "$remote_branch..$current_branch" 2>/dev/null || echo "0")
            elif [[ $(git rev-list --count HEAD 2>/dev/null || echo "0") -gt 0 ]]; then
              unpushed_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
            fi
          fi
          
          echo "   Branch: $current_branch" >> "$report_file"
          [[ $uncommitted_count -gt 0 ]] && echo "   Uncommitted files: $uncommitted_count" >> "$report_file"
          [[ $unpushed_count -gt 0 ]] && echo "   Unpushed commits: $unpushed_count" >> "$report_file"
          echo "" >> "$report_file"
          
          cd "$base_path" || return 1
        done
      fi
      
      # Add up-to-date repositories
      cat >> "$report_file" << EOF

REPOSITORIES UP-TO-DATE:
EOF
      
      echo ""
      print_status "Repositories up-to-date:"
      
      # Find all repos and determine which are up-to-date
      while IFS= read -r -d '' git_dir; do
        repo_path=$(dirname "$git_dir")
        repo_name=$(basename "$repo_path")
        
        # Check if this repo is in the "needs push" list
        local needs_update=false
        for repo_info in "${repos_needing_push[@]}"; do
          IFS='|' read -r check_path status_info <<< "$repo_info"
          if [[ "$check_path" == "$repo_path" ]]; then
            needs_update=true
            break
          fi
        done
        
        if [[ "$needs_update" == "false" ]]; then
          echo "[UP-TO-DATE] $repo_name - No updates required"
          echo "[UP-TO-DATE] $repo_name - No updates required" >> "$report_file"
          echo "   Path: $repo_path" >> "$report_file"
          
          cd "$repo_path" || continue
          local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
          local last_commit=$(git log -1 --format="%h - %s (%cr)" 2>/dev/null || echo "No commits")
          
          echo "   Branch: $current_branch" >> "$report_file"
          echo "   Last commit: $last_commit" >> "$report_file"
          echo "" >> "$report_file"
          
          cd "$base_path" || return 1
        fi
      done < <(find "$base_path" -name ".git" -type d -print0 2>/dev/null)
      
      # Add report footer
      cat >> "$report_file" << EOF

========================================
End of Report
Generated by: GitHub Repository Manager
========================================
EOF
      
      echo ""
      print_success "Report generated successfully!"
      echo "Report saved to: $report_file"
      
      read -p "Do you want to view the report now? [y/N]: " view_report
      if [[ "$view_report" =~ ^[Yy]$ ]]; then
        echo ""
        echo "=========================================="
        cat "$report_file"
        echo "=========================================="
      fi
      
      read -p "Do you want to save the report to a custom location? [y/N]: " save_custom
      if [[ "$save_custom" =~ ^[Yy]$ ]]; then
        read -p "Enter full path for report file: " custom_path
        if [[ -n "$custom_path" ]]; then
          if cp "$report_file" "$custom_path" 2>/dev/null; then
            print_success "Report saved to: $custom_path"
          else
            print_error "Failed to save report to: $custom_path"
            print_info "Report remains available at: $report_file"
          fi
        fi
      fi
      ;;
      
    4)
      print_status "Returning to main menu..."
      return 0
      ;;
      
    *)
      print_error "Invalid selection"
      return 1
      ;;
  esac
}

# Function to generate a quick status report for all repositories
generate_repository_report() {
  echo ""
  print_status "Generating Quick Repository Status Report..."
  local base_path
  read -p "Enter base path to scan (default: current directory): " base_path
  base_path="${base_path:-.}"

  if [[ ! -d "$base_path" ]]; then
    print_error "Directory not found: $base_path"
    return 1
  fi

  cd "$base_path" || return 1

  local total_repos=0
  local needs_update=0
  local up_to_date=0
  local report_timestamp=$(date "+%Y-%m-%d %H:%M:%S")
  
  echo ""
  echo "=========================================="
  echo "Git Repository Status Report"
  echo "Generated: $report_timestamp"
  echo "Scan Path: $base_path"
  echo "=========================================="
  
  # Create arrays to store results
  local needs_update_list=()
  local up_to_date_list=()

  # Scan all git repositories
  while IFS= read -r -d '' git_dir; do
    repo_path=$(dirname "$git_dir")
    repo_name=$(basename "$repo_path")
    ((total_repos++))
    
    cd "$repo_path" 2>/dev/null || continue
    
    # Check for changes
    local has_changes=false
    local status_info=""
    
    # Check for uncommitted changes
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null || [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
      has_changes=true
      local uncommitted_count=$(git status --porcelain 2>/dev/null | wc -l)
      status_info+="$uncommitted_count uncommitted files"
    fi
    
    # Check for unpushed commits
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ -n "$current_branch" && "$current_branch" != "HEAD" ]]; then
      local remote_branch=$(git rev-parse --abbrev-ref "$current_branch@{upstream}" 2>/dev/null || echo "")
      if [[ -n "$remote_branch" ]]; then
        local ahead_count=$(git rev-list --count "$remote_branch..$current_branch" 2>/dev/null || echo "0")
        if [[ "$ahead_count" -gt 0 ]]; then
          has_changes=true
          [[ -n "$status_info" ]] && status_info+=", "
          status_info+="$ahead_count unpushed commits"
        fi
      elif [[ $(git rev-list --count HEAD 2>/dev/null || echo "0") -gt 0 ]]; then
        has_changes=true
        [[ -n "$status_info" ]] && status_info+=", "
        local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        status_info+="$commit_count commits (no upstream)"
      fi
    fi
    
    if [[ "$has_changes" == "true" ]]; then
      ((needs_update++))
      needs_update_list+=("$repo_name|$repo_path|$status_info")
    else
      ((up_to_date++))
      local last_commit=$(git log -1 --format="%h - %s (%cr)" 2>/dev/null || echo "No commits")
      up_to_date_list+=("$repo_name|$repo_path|$current_branch|$last_commit")
    fi
    
    cd "$base_path" || return 1
  done < <(find "$base_path" -name ".git" -type d -print0 2>/dev/null)

  # Display summary
  echo ""
  echo "SUMMARY:"
  echo "- Total repositories: $total_repos"
  echo "- Need updates: $needs_update"
  echo "- Up-to-date: $up_to_date"
  
  # Show repositories needing updates
  if [[ $needs_update -gt 0 ]]; then
    echo ""
    echo "REPOSITORIES NEEDING UPDATES:"
    echo "----------------------------------------"
    for repo_info in "${needs_update_list[@]}"; do
      IFS='|' read -r name path status <<< "$repo_info"
      echo "[NEEDS UPDATE] $name"
      echo "   Status: $status"
      echo "   Path: $path"
      echo ""
    done
  fi
  
  # Show up-to-date repositories  
  if [[ $up_to_date -gt 0 ]]; then
    echo ""
    echo "REPOSITORIES UP-TO-DATE:"
    echo "----------------------------------------"
    for repo_info in "${up_to_date_list[@]}"; do
      IFS='|' read -r name path branch last_commit <<< "$repo_info"
      echo "[UP-TO-DATE] $name"
      echo "   Branch: $branch"
      echo "   Last: $last_commit"
      echo "   Path: $path"
      echo ""
    done
  fi
  
  echo "=========================================="
  
  # Option to save report
  echo ""
  read -p "Do you want to save this report to a file? [y/N]: " save_report
  if [[ "$save_report" =~ ^[Yy]$ ]]; then
    local report_file="git_status_report_$(date +%Y%m%d_%H%M%S).txt"
    read -p "Enter filename [$report_file]: " custom_filename
    report_file=${custom_filename:-$report_file}
    
    {
      echo "Git Repository Status Report"
      echo "Generated: $report_timestamp" 
      echo "Scan Path: $base_path"
      echo "=========================================="
      echo ""
      echo "SUMMARY:"
      echo "- Total repositories: $total_repos"
      echo "- Need updates: $needs_update"
      echo "- Up-to-date: $up_to_date"
      echo ""
      
      if [[ $needs_update -gt 0 ]]; then
        echo "REPOSITORIES NEEDING UPDATES:"
        echo "----------------------------------------"
        for repo_info in "${needs_update_list[@]}"; do
          IFS='|' read -r name path status <<< "$repo_info"
          echo "[NEEDS UPDATE] $name - $status"
          echo "   Path: $path"
          echo ""
        done
      fi
      
      if [[ $up_to_date -gt 0 ]]; then
        echo "REPOSITORIES UP-TO-DATE:"
        echo "----------------------------------------"
        for repo_info in "${up_to_date_list[@]}"; do
          IFS='|' read -r name path branch last_commit <<< "$repo_info"
          echo "[UP-TO-DATE] $name ($branch) - $last_commit"
          echo "   Path: $path"
          echo ""
        done
      fi
      
      echo "=========================================="
      echo "Report generated by GitHub Repository Manager"
    } > "$report_file"
    
    if [[ -f "$report_file" ]]; then
      print_success "Report saved to: $report_file"
    else
      print_error "Failed to save report"
    fi
  fi
}

# Function to fix git repository ownership issues
fix_git_ownership() {
  local repo_path="$1"
  if [[ -d "$repo_path/.git" ]]; then
    # Check if .git directory has correct ownership
    local git_owner=$(stat -c '%U' "$repo_path/.git" 2>/dev/null || echo "unknown")
    local current_user=$(whoami)
    
    if [[ "$git_owner" != "$current_user" ]]; then
      print_warning "Git repository ownership needs fixing (owned by: $git_owner, current user: $current_user)"
      if sudo chown -R "$current_user:$current_user" "$repo_path/.git/" 2>/dev/null; then
        print_success "Fixed git repository ownership"
      else
        print_warning "Could not fix git ownership automatically. You may need to run: sudo chown -R $current_user:$current_user $repo_path/.git/"
      fi
    fi
  fi
}

# Function to setup git configuration if missing
setup_git_config() {
  local gh_user="$1"
  
  # Check if git user.name is configured
  if ! git config user.name >/dev/null 2>&1; then
    print_status "Setting up git user.name..."
    git config user.name "$gh_user"
  fi
  
  # Check if git user.email is configured
  if ! git config user.email >/dev/null 2>&1; then
    print_status "Setting up git user.email..."
    local email
    read -p "Enter your email address for git commits: " email
    if [[ -n "$email" ]]; then
      git config user.email "$email"
    else
      print_warning "No email provided. Using default format."
      git config user.email "${gh_user}@users.noreply.github.com"
    fi
  fi
  
  # Set pull strategy to avoid future merge issues
  git config pull.rebase false 2>/dev/null || true
}

# Function to handle divergent branches and unrelated histories
handle_repository_sync() {
  local repo_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  
  print_status "Setting up upstream tracking..."
  if ! git branch --set-upstream-to=origin/main main 2>/dev/null; then
    print_warning "Could not set upstream tracking (this is normal for new repositories)"
  fi
  
  # Try to pull from remote
  print_status "Checking for remote changes..."
  if git pull 2>/dev/null; then
    print_success "Repository synchronized successfully"
  elif git pull --no-rebase --allow-unrelated-histories 2>/dev/null; then
    print_warning "Merged unrelated histories from remote repository"
  else
    print_warning "Could not automatically merge remote changes. This may be a new repository."
    
    # Check if there are conflicts
    if git status --porcelain | grep -q "^UU\|^AA\|^DD"; then
      print_error "Merge conflicts detected. Please resolve manually or choose an option:"
      echo "1) Keep local version (recommended for initial setup)"
      echo "2) Keep remote version"
      echo "3) Resolve manually"
      read -p "Enter choice (1-3): " conflict_choice
      
      case $conflict_choice in
        1)
          print_status "Keeping local version and force pushing..."
          git merge --abort 2>/dev/null || true
          git push --force-with-lease origin main
          ;;
        2)
          print_status "Keeping remote version..."
          git reset --hard origin/main
          ;;
        3)
          print_warning "Please resolve conflicts manually and run 'git commit' when done"
          return 1
          ;;
        *)
          print_error "Invalid choice. Aborting merge."
          git merge --abort 2>/dev/null || true
          ;;
      esac
    fi
  fi
}

# Function to show help
show_help() {
  echo "GitHub Repository Manager v4.2.3"
  echo ""
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -h, --help        Show this help message"
  echo "  -c, --create      Go directly to repository creation"
  echo "  -d, --delete      Go directly to repository deletion"
  echo "  -l, --clone       Clone existing repository"
  echo "  -b, --bulk-clone  Bulk clone all user repositories into organized folders"
  echo "  -f, --fix         Fix common git repository issues"
  echo "  -a, --auto-commit Auto-commit and push multiple repositories"
  echo "  -p, --protect     Set up branch protection rules"
  echo "  -m, --manage-pr   Manage pull requests (list, merge, close)"
  echo "  -g, --ga-cleanup  Cleanup repository for GA release (with backup)"
  echo "  -r, --restore     Restore repository from backup"
  echo ""
  echo "Interactive Mode (default):"
  echo "  Run without arguments to see the menu interface"
  echo ""
  echo "Examples:"
  echo "  $0                 # Show interactive menu"
  echo "  $0 --create        # Create new repository"
  echo "  $0 --delete        # Delete repository"
  echo "  $0 --clone         # Clone existing repository"
  echo "  $0 --bulk-clone    # Bulk clone all user repositories into organized folders"
  echo "  $0 --fix           # Fix git repository issues"
  echo "  $0 --auto-commit   # Auto-commit multiple repositories"
  echo "  $0 --protect       # Set up branch protection"
  echo "  $0 --manage-pr     # Manage pull requests"
  echo "  $0 --ga-cleanup    # Cleanup repository for GA release"
  echo "  $0 --restore       # Restore repository from backup"
  echo "  $0 --help          # Show this help"
  echo ""
  echo "Requirements:"
  echo "  - GitHub Personal Access Token"
  echo "  - curl and git commands available"
  echo "  - For creation: token needs 'repo' scope"
  echo "  - For deletion: token needs 'delete_repo' scope"
  echo "  - For protection: token needs 'repo' scope with admin permissions"
  echo ""
  echo "Git Issue Fixes Include:"
  echo "  - File ownership problems"
  echo "  - Missing upstream tracking"
  echo "  - Git configuration setup"
  echo "  - Merge conflict resolution"
  echo "  - Unrelated histories handling"
  echo ""
  echo "Repository Clone Features:"
  echo "  - Multiple authentication methods (HTTPS, HTTPS with token, SSH)"
  echo "  - Branch selection and clone depth options"
  echo "  - Full clone, shallow clone, or custom depth cloning"
  echo "  - Automatic post-clone repository information display"
  echo "  - Optional git user configuration for local repository"
  echo "  - Additional remote setup capability"
  echo "  - Custom local directory naming"
  echo "  - Target directory selection"
  echo ""
  echo "Bulk Clone Features:"
  echo "  - Clone all repositories for a specific GitHub user"
  echo "  - Support for public and private repositories"
  echo "  - Repository filtering options (skip forks, only forks, public/private only)"
  echo "  - Pagination support for users with many repositories"
  echo "  - HTTPS and SSH clone methods"
  echo "  - Full or shallow clone options"
  echo "  - Existing repository handling (skip, overwrite, abort)"
  echo "  - Comprehensive progress reporting and error handling"
  echo ""
  echo "Auto-Commit Features:"
  echo "  - Batch process multiple repositories"
  echo "  - Dry-run mode to preview changes"
  echo "  - Configurable exclude directories"
  echo "  - Detailed progress reporting"
  echo ""
  echo "Branch Protection Features:"
  echo "  - Require pull request reviews"
  echo "  - Enforce status checks"
  echo "  - Restrict direct pushes to main branch"
  echo "  - Admin enforcement options"
  echo "  - Custom protection configurations"
  echo ""
  echo "Pull Request Management Features:"
  echo "  - List all open pull requests with details"
  echo "  - Get comprehensive PR information (author, changes, status)"
  echo "  - Merge PRs with multiple strategies:"
  echo "    * Merge commit (preserves full branch history)"
  echo "    * Squash and merge (combines all commits into one)"
  echo "    * Rebase and merge (replays commits without merge commit)"
  echo "  - Close PRs without merging (with optional reason)"
  echo "  - Automatic branch cleanup after merging"
  echo "  - Conflict detection and warnings"
  echo ""
  echo "GA Cleanup Features:"
  echo "  - Automatic backup creation (tar.gz in ~/backup)"
  echo "  - Remove unnecessary files (logs, temp files, cache, etc.)"
  echo "  - Check syntax of Python, Shell, YAML, and JSON files"
  echo "  - Clean git history (optional fresh start)"
  echo "  - Repository optimization and compression"
  echo "  - Create/update .gitignore with best practices"
  echo "  - Large file detection and removal options"
  echo ""
  echo "Backup & Restore Features:"
  echo "  - Automatic timestamped backups before cleanup"
  echo "  - Dynamic list of available backup archives"
  echo "  - Restore to timestamped directories"
  echo "  - Backup integrity verification"
  echo "  - Repository information display after restore"
}

# Function to remove a repository both from GitHub and locally
remove_repository() {
  echo ""
  echo "=========================================="
  echo " GitHub Repository Removal Tool"
  echo "=========================================="
  echo ""
  print_warning "[WARNING] WARNING: This will permanently delete the repository!"
  print_warning "[WARNING] This action CANNOT be undone!"
  echo ""
  
  # Get repository information
  read -p "Enter repository name to delete: " repo_name
  if [[ -z "$repo_name" ]]; then
    print_error "Repository name cannot be empty"
    return 1
  fi
  
  read -p "Enter GitHub username/organization: " gh_user
  if [[ -z "$gh_user" ]]; then
    print_error "Username/organization cannot be empty"
    return 1
  fi
  
  read -p "Enter GitHub domain (press Enter for github.com): " github_url
  if [[ -z "$github_url" ]]; then
    github_url="github.com"
    api_url="https://api.github.com"
  else
    # Clean up domain input
    github_url=${github_url#https://}
    github_url=${github_url#http://}
    github_url=${github_url%/}
    
    if [[ "$github_url" == "github.com" ]]; then
      api_url="https://api.github.com"
    else
      api_url="https://$github_url/api/v3"
    fi
  fi
  
  # Get GitHub token
  echo ""
  print_status "GitHub Token Required (needs 'delete_repo' scope)"
  read -s -p "Enter your GitHub Personal Access Token: " gh_token
  echo ""
  
  if [[ -z "$gh_token" ]]; then
    print_error "GitHub token cannot be empty"
    return 1
  fi
  
  # Final confirmation
  echo ""
  print_warning "You are about to delete:"
  echo "  Repository: ${RED}$gh_user/$repo_name${NC}"
  echo "  GitHub URL: ${RED}https://$github_url/$gh_user/$repo_name${NC}"
  echo ""
  read -p "Type 'DELETE' to confirm permanent removal: " confirmation
  
  if [[ "$confirmation" != "DELETE" ]]; then
    print_status "Operation cancelled by user"
    return 0
  fi
  
  # Check if local directory exists and get its path
  local_repo_path=""
  if [[ -d "$repo_name" ]]; then
    local_repo_path="$(pwd)/$repo_name"
    print_status "Found local repository at: $local_repo_path"
  elif [[ -d "../$repo_name" ]]; then
    local_repo_path="$(cd .. && pwd)/$repo_name"
    print_status "Found local repository at: $local_repo_path"
  else
    read -p "Enter full path to local repository (or press Enter to skip local deletion): " local_repo_path
  fi
  
  # Step 1: Delete from GitHub
  print_status "Deleting repository from GitHub..."
  http_response=$(curl -s -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    "$api_url/repos/$gh_user/$repo_name" \
    -o /tmp/github_delete_response.json)
  
  if [[ "$http_response" == "204" ]]; then
    print_success "[SUCCESS] Repository successfully deleted from GitHub!"
  elif [[ "$http_response" == "404" ]]; then
    print_warning "Repository not found on GitHub (may already be deleted)"
  elif [[ "$http_response" == "403" ]]; then
    print_error "[ERROR] Access denied. Check your token permissions (needs 'delete_repo' scope)"
    cat /tmp/github_delete_response.json 2>/dev/null || true
    rm -f /tmp/github_delete_response.json
    return 1
  else
    print_error "[ERROR] Failed to delete repository from GitHub (HTTP: $http_response)"
    cat /tmp/github_delete_response.json 2>/dev/null || true
    rm -f /tmp/github_delete_response.json
    return 1
  fi
  
  rm -f /tmp/github_delete_response.json
  
  # Step 2: Delete local repository if path provided
  if [[ -n "$local_repo_path" && -d "$local_repo_path" ]]; then
    print_status "Deleting local repository..."
    
    # Verify it's a git repository
    if [[ -d "$local_repo_path/.git" ]]; then
      # Remove read-only permissions that might prevent deletion
      chmod -R +w "$local_repo_path" 2>/dev/null || true
      
      # Remove the directory
      if rm -rf "$local_repo_path"; then
        print_success "[SUCCESS] Local repository deleted: $local_repo_path"
      else
        print_error "[ERROR] Failed to delete local repository: $local_repo_path"
        print_error "You may need to delete it manually"
        return 1
      fi
    else
      print_warning "Directory exists but is not a Git repository: $local_repo_path"
      read -p "Delete anyway? (y/N): " delete_anyway
      if [[ "$delete_anyway" =~ ^[Yy]$ ]]; then
        chmod -R +w "$local_repo_path" 2>/dev/null || true
        if rm -rf "$local_repo_path"; then
          print_success "[SUCCESS] Directory deleted: $local_repo_path"
        else
          print_error "[ERROR] Failed to delete directory: $local_repo_path"
          return 1
        fi
      else
        print_status "Local directory deletion skipped"
      fi
    fi
  elif [[ -n "$local_repo_path" ]]; then
    print_warning "Local repository path does not exist: $local_repo_path"
  else
    print_status "Local repository deletion skipped"
  fi
  
  echo ""
  echo "=========================================="
  print_success "Repository removal completed!"
  echo "=========================================="
  
  return 0
}

# Function to create a repository (existing functionality)
create_repository() {
  echo ""
  echo "GitHub Instance Configuration:"
  echo " For GitHub.com: Just press Enter"
  echo " For Enterprise: Enter domain only (e.g., github.company.com)"
  echo ""

  read -p "Enter GitHub domain (press Enter for github.com): " github_url
  if [[ -z "$github_url" ]]; then
    github_url="github.com"
    api_url="https://api.github.com"
  else
    # Remove protocol if provided
    github_url=${github_url#https://}
    github_url=${github_url#http://}
    # Remove trailing slash if present
    github_url=${github_url%/}

    # Extract domain from URL (remove username/org paths)
    if [[ "$github_url" == *"github.com"* ]]; then
      github_url="github.com"
    else
      # For enterprise instances, take only the domain part
      github_url=$(echo "$github_url" | cut -d'/' -f1)
    fi

    # Set API URL based on GitHub instance
    if [[ "$github_url" == "github.com" ]]; then
      api_url="https://api.github.com"
    else
      api_url="https://$github_url/api/v3"
    fi
  fi

  print_status "Using GitHub instance: ${BLUE}$github_url${NC}"
  print_status "API endpoint: ${BLUE}$api_url${NC}"

  read -p "Enter full path to your local project directory: " project_path
  read -p "Enter your GitHub username: " gh_user
  read -s -p "Enter your GitHub personal access token: " gh_token
  echo ""

  # Validate inputs
  if [[ -z "$project_path" || -z "$gh_user" || -z "$gh_token" ]]; then
    print_error "All fields are required!"
    exit 1
  fi

  # Extract repo name from the last folder in the path
  repo_name=$(basename "$project_path")
  repo_url="https://${gh_token}@${github_url}/$gh_user/$repo_name.git"

  # Navigate to the project directory
  print_status "Navigating to project directory: $project_path"
  cd "$project_path" || {
    print_error "Directory not found: $project_path"
    exit 1
  }

  # Fix git ownership issues if they exist
  fix_git_ownership "$project_path"

  # Initialize Git repo if not already
  if [ ! -d ".git" ]; then
    print_status "Initializing Git repository..."
    git init
    git config init.defaultBranch main
  else
    print_status "Git repository already exists"
  fi

  # Setup git configuration
  setup_git_config "$gh_user"

  # Check if there are any files to commit
  if git diff --cached --exit-code >/dev/null && git diff --exit-code >/dev/null && [ -z "$(git ls-files)" ]; then
    print_warning "No files found to commit. Adding all files..."
    git add .
  fi

  # Check if there are uncommitted changes
  if ! git diff --cached --exit-code >/dev/null; then
    print_status "Committing changes..."
    local commit_cmd="git commit -m \"Initial commit - automated upload\""
    if should_use_no_verify "$(pwd)"; then
      commit_cmd="git commit --no-verify -m \"Initial commit - automated upload\""
      print_status "Using --no-verify due to template variables or README passwords detected"
    fi
    eval "$commit_cmd"
  elif [ -n "$(git ls-files)" ] && [ -z "$(git log --oneline -1 2>/dev/null)" ]; then
    print_status "Creating initial commit..."
    git add .
    local commit_cmd="git commit -m \"Initial commit - automated upload\""
    if should_use_no_verify "$(pwd)"; then
      commit_cmd="git commit --no-verify -m \"Initial commit - automated upload\""
      print_status "Using --no-verify due to template variables or README passwords detected"
    fi
    eval "$commit_cmd"
  else
    print_status "Repository is already committed and up to date"
  fi

  # Create repo on GitHub using API
  print_status "Creating GitHub repository: $repo_name"
  response=$(curl -s -w "%{http_code}" -u "$gh_user:$gh_token" \
    "$api_url/user/repos" \
    -d "{\"name\":\"$repo_name\",\"private\":false}" \
    -o /tmp/github_response.json)

  http_code="${response: -3}"

  if [[ "$http_code" == "201" ]]; then
    print_success "GitHub repository created successfully!"
  elif [[ "$http_code" == "422" ]]; then
    if grep -q "name already exists" /tmp/github_response.json; then
      print_warning "Repository already exists on GitHub. Continuing with push..."
    else
      print_error "Repository creation failed. Response:"
      cat /tmp/github_response.json
      exit 1
    fi
  else
    print_error "Failed to create repository. HTTP Code: $http_code"
    cat /tmp/github_response.json
    exit 1
  fi

  # Add remote if it doesn't exist
  if ! git remote get-url origin >/dev/null 2>&1; then
    print_status "Adding remote origin..."
    git remote add origin "$repo_url"
  else
    print_status "Remote origin already exists, updating URL..."
    git remote set-url origin "$repo_url"
  fi

  # Ensure we're on main branch
  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "main" ]]; then
    print_status "Switching to main branch..."
    git branch -M main
  fi

  # Push to GitHub
  print_status "Pushing to GitHub..."
  if git push -u origin main 2>/dev/null; then
    print_success "Successfully pushed to GitHub!"
  else
    print_warning "Initial push failed. Attempting advanced push strategies..."
    
    # Try pushing with lease protection first
    if git push --force-with-lease origin main 2>/dev/null; then
      print_success "Successfully force-pushed to GitHub with lease protection!"
    else
      print_warning "Force push with lease failed. Trying credential helper method..."
      # Try using credential helper
      git config credential.helper store
      echo "https://${gh_user}:${gh_token}@${github_url}" > ~/.git-credentials

      if git push -u origin main 2>/dev/null; then
        print_success "Successfully pushed to GitHub!"
        # Clean up credentials
        rm -f ~/.git-credentials
        git config --unset credential.helper
      elif git push --force-with-lease origin main 2>/dev/null; then
        print_success "Successfully force-pushed to GitHub!"
        # Clean up credentials
        rm -f ~/.git-credentials
        git config --unset credential.helper
      else
        print_error "Failed to push to GitHub. Please check your token permissions."
        print_error "Make sure your token has 'repo' scope enabled."
        rm -f ~/.git-credentials
        git config --unset credential.helper 2>/dev/null || true
        exit 1
      fi
    fi
  fi

  # Handle repository synchronization after initial push
  if [[ "$http_code" == "422" ]]; then
    print_status "Repository already exists. Attempting to synchronize..."
    handle_repository_sync "$repo_url" "$gh_user" "$repo_name"
  fi

  # Clean up
  rm -f /tmp/github_response.json

  echo ""
  echo "=========================================="
  print_success "Project '$repo_name' has been successfully pushed to GitHub!"
  echo "Repository URL: ${BLUE}https://$github_url/$gh_user/$repo_name${NC}"
  echo "=========================================="
}

# Wrapper to call create_repository with a pre-filled project path
create_repository_with_path() {
  local project_path="$1"
  echo ""
  echo "GitHub Instance Configuration:"
  echo " For GitHub.com: Just press Enter"
  echo " For Enterprise: Enter domain only (e.g., github.company.com)"
  echo ""

  read -p "Enter GitHub domain (press Enter for github.com): " github_url
  if [[ -z "$github_url" ]]; then
    github_url="github.com"
    api_url="https://api.github.com"
  else
    github_url=${github_url#https://}
    github_url=${github_url#http://}
    github_url=${github_url%/}
    if [[ "$github_url" == "github.com" ]]; then
      api_url="https://api.github.com"
    else
      api_url="https://$github_url/api/v3"
    fi
  fi

  print_status "Using GitHub instance: ${BLUE}$github_url${NC}"
  print_status "API endpoint: ${BLUE}$api_url${NC}"

  # Use the supplied project path
  local gh_user
  read -p "Enter your GitHub username: " gh_user
  local gh_token
  read -s -p "Enter your GitHub personal access token: " gh_token
  echo ""

  if [[ -z "$project_path" || -z "$gh_user" || -z "$gh_token" ]]; then
    print_error "All fields are required!"
    exit 1
  fi

  # Extract repo name from the last folder in the path
  repo_name=$(basename "$project_path")
  repo_url="https://${gh_token}@${github_url}/$gh_user/$repo_name.git"

  # Navigate to the project directory
  print_status "Navigating to project directory: $project_path"
  cd "$project_path" || {
    print_error "Directory not found: $project_path"
    exit 1
  }

  # Fix git ownership issues if they exist
  fix_git_ownership "$project_path"

  # Initialize Git repo if not already
  if [ ! -d ".git" ]; then
    print_status "Initializing Git repository..."
    git init
    git config init.defaultBranch main
  else
    print_status "Git repository already exists"
  fi

  # Setup git configuration
  setup_git_config "$gh_user"

  # Check if there are any files to commit
  if git diff --cached --exit-code >/dev/null && git diff --exit-code >/dev/null && [ -z "$(git ls-files)" ]; then
    print_warning "No files found to commit. Adding all files..."
    git add .
  fi

  # Check if there are uncommitted changes
  if ! git diff --cached --exit-code >/dev/null; then
    print_status "Committing changes..."
    local commit_cmd="git commit -m \"Initial commit - automated upload\""
    if should_use_no_verify "$(pwd)"; then
      commit_cmd="git commit --no-verify -m \"Initial commit - automated upload\""
      print_status "Using --no-verify due to template variables or README passwords detected"
    fi
    eval "$commit_cmd"
  elif [ -n "$(git ls-files)" ] && [ -z "$(git log --oneline -1 2>/dev/null)" ]; then
    print_status "Creating initial commit..."
    git add .
    local commit_cmd="git commit -m \"Initial commit - automated upload\""
    if should_use_no_verify "$(pwd)"; then
      commit_cmd="git commit --no-verify -m \"Initial commit - automated upload\""
      print_status "Using --no-verify due to template variables or README passwords detected"
    fi
    eval "$commit_cmd"
  else
    print_status "Repository is already committed and up to date"
  fi

  print_status "Creating GitHub repository: $repo_name"
  response=$(curl -s -w "%{http_code}" -u "$gh_user:$gh_token" \
    "$api_url/user/repos" \
    -d "{\"name\":\"$repo_name\",\"private\":false}" \
    -o /tmp/github_response.json)

  http_code="${response: -3}"

  if [[ "$http_code" == "201" ]]; then
    print_success "GitHub repository created successfully!"
  elif [[ "$http_code" == "422" ]]; then
    if grep -q "name already exists" /tmp/github_response.json; then
      print_warning "Repository already exists on GitHub. Continuing with push..."
    else
      print_error "Repository creation failed. Response:"
      cat /tmp/github_response.json
      exit 1
    fi
  else
    print_error "Failed to create repository. HTTP Code: $http_code"
    cat /tmp/github_response.json
    exit 1
  fi

  if ! git remote get-url origin >/dev/null 2>&1; then
    print_status "Adding remote origin..."
    git remote add origin "$repo_url"
  else
    print_status "Remote origin already exists, updating URL..."
    git remote set-url origin "$repo_url"
  fi

  current_branch=$(git branch --show-current)
  if [[ "$current_branch" != "main" ]]; then
    print_status "Switching to main branch..."
    git branch -M main
  fi

  print_status "Pushing to GitHub..."
  if git push -u origin main 2>/dev/null; then
    print_success "Successfully pushed to GitHub!"
  else
    print_warning "Initial push failed. Attempting advanced push strategies..."
    
    # Try pushing with lease protection first
    if git push --force-with-lease origin main 2>/dev/null; then
      print_success "Successfully force-pushed to GitHub with lease protection!"
    else
      print_warning "Force push with lease failed. Trying credential helper method..."
      # Try using credential helper
      git config credential.helper store
      echo "https://${gh_user}:${gh_token}@${github_url}" > ~/.git-credentials

      if git push -u origin main 2>/dev/null; then
        print_success "Successfully pushed to GitHub!"
        # Clean up credentials
        rm -f ~/.git-credentials
        git config --unset credential.helper
      elif git push --force-with-lease origin main 2>/dev/null; then
        print_success "Successfully force-pushed to GitHub!"
        # Clean up credentials
        rm -f ~/.git-credentials
        git config --unset credential.helper
      else
        print_error "Failed to push to GitHub. Please check your token permissions."
        print_error "Make sure your token has 'repo' scope enabled."
        rm -f ~/.git-credentials
        git config --unset credential.helper 2>/dev/null || true
        exit 1
      fi
    fi
  fi

  # Handle repository synchronization after initial push
  if [[ "$http_code" == "422" ]]; then
    print_status "Repository already exists. Attempting to synchronize..."
    handle_repository_sync "$repo_url" "$gh_user" "$repo_name"
  fi

  # Clean up
  rm -f /tmp/github_response.json

  echo ""
  echo "=========================================="
  print_success "Project '$repo_name' has been successfully pushed to GitHub!"
  echo "Repository URL: ${BLUE}https://$github_url/$gh_user/$repo_name${NC}"
  echo "=========================================="
}

# Function to fix common git issues in existing repositories
fix_git_issues() {
  echo ""
  echo "=========================================="
  echo " Git Repository Issue Resolver"
  echo "=========================================="
  echo ""
  
  read -p "Enter full path to your local repository: " repo_path
  if [[ ! -d "$repo_path" ]]; then
    print_error "Directory not found: $repo_path"
    return 1
  fi
  
  cd "$repo_path" || {
    print_error "Cannot navigate to: $repo_path"
    return 1
  }
  
  if [[ ! -d ".git" ]]; then
    print_error "Not a git repository: $repo_path"
    return 1
  fi
  
  print_status "Analyzing repository: $repo_path"
  
  # Fix ownership issues
  fix_git_ownership "$repo_path"
  
  # Check for upstream tracking
  if ! git rev-parse --abbrev-ref @{u} >/dev/null 2>&1; then
    print_warning "No upstream tracking configured"
    echo "Available remotes:"
    git remote -v
    echo ""
    read -p "Enter remote name (usually 'origin'): " remote_name
    read -p "Enter branch name (usually 'main'): " branch_name
    
    if [[ -n "$remote_name" && -n "$branch_name" ]]; then
      if git branch --set-upstream-to="$remote_name/$branch_name" "$branch_name"; then
        print_success "Upstream tracking configured: $remote_name/$branch_name"
      else
        print_error "Failed to set upstream tracking"
      fi
    fi
  fi
  
  # Check git configuration
  if ! git config user.name >/dev/null 2>&1; then
    read -p "Enter your name for git commits: " user_name
    if [[ -n "$user_name" ]]; then
      git config user.name "$user_name"
      print_success "Set git user.name: $user_name"
    fi
  fi
  
  if ! git config user.email >/dev/null 2>&1; then
    read -p "Enter your email for git commits: " user_email
    if [[ -n "$user_email" ]]; then
      git config user.email "$user_email"
      print_success "Set git user.email: $user_email"
    fi
  fi
  
  # Set pull strategy to avoid future conflicts
  git config pull.rebase false
  print_success "Set pull strategy to merge (avoids rebase conflicts)"
  
  # Test connectivity
  print_status "Testing repository connectivity..."
  if git fetch --dry-run 2>/dev/null; then
    print_success "Repository connectivity OK"
  else
    print_warning "Cannot connect to remote repository"
    echo "This could be due to:"
    echo "  - Network issues"
    echo "  - Authentication problems"
    echo "  - Incorrect remote URL"
    echo ""
    echo "Current remote URLs:"
    git remote -v
  fi
  
  # Show repository status
  echo ""
  print_status "Repository status:"
  git status
  
  echo ""
  print_success "Git repository analysis completed!"
}

# Function for auto-commit and push across multiple repositories
auto_commit_repositories() {
  echo ""
  echo "=========================================="
  echo " Auto-Commit & Push Multiple Repositories"
  echo "=========================================="
  echo ""
  
  # Get configuration from user
  read -p "Enter base directory containing git repositories [${HOME}/Downloads/GIT]: " git_base_dir
  git_base_dir=${git_base_dir:-"${HOME}/Downloads/GIT"}
  
  if [[ ! -d "$git_base_dir" ]]; then
    print_error "Directory not found: $git_base_dir"
    return 1
  fi
  
  read -p "Enter commit message [auto commit]: " commit_msg
  commit_msg=${commit_msg:-"auto commit"}
  
  read -p "Enter directories to exclude (space-separated) [Alex .vscode]: " excluded_input
  IFS=' ' read -ra excluded_dirs <<< "${excluded_input:-Alex .vscode}"
  
  read -p "Enter GitHub username: " gh_user
  if [[ -z "$gh_user" ]]; then
    print_error "GitHub username is required"
    return 1
  fi
  
  # Check for GitHub token
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    print_warning "GITHUB_TOKEN environment variable not found"
    read -s -p "Enter your GitHub Personal Access Token: " gh_token
    echo ""
    if [[ -z "$gh_token" ]]; then
      print_error "GitHub token is required"
      return 1
    fi
  else
    gh_token="$GITHUB_TOKEN"
    print_success "Using GITHUB_TOKEN from environment"
  fi
  
  # Ask for dry run or actual execution
  echo ""
  echo "Choose execution mode:"
  echo "1) Dry run (show what would be done)"
  echo "2) Execute auto-commit and push"
  read -p "Enter choice (1-2): " exec_mode
  
  case $exec_mode in
    1) dry_run_repos "$git_base_dir" "$commit_msg" "$gh_user" "$gh_token" ;;
    2) execute_auto_commit "$git_base_dir" "$commit_msg" "$gh_user" "$gh_token" ;;
    *) print_error "Invalid choice"; return 1 ;;
  esac
}

# Function to perform dry run of auto-commit
dry_run_repos() {
  local base_dir="$1"
  local commit_msg="$2"
  local gh_user="$3"
  local gh_token="$4"
  
  print_status "DRY RUN MODE - No changes will be made"
  print_status "Base directory: $base_dir"
  print_status "Commit message: '$commit_msg'"
  echo ""
  
  cd "$base_dir" || return 1
  
  local total_repos=0
  local repos_with_changes=0
  
  for dir in */; do
    dir_name="${dir%/}"
    
    # Check if directory should be excluded
    local excluded=false
    for excl in "${excluded_dirs[@]}"; do
      if [[ "$dir_name" == "$excl" ]]; then
        excluded=true
        break
      fi
    done
    
    if [[ "$excluded" == "true" ]]; then
      print_warning "Would skip excluded directory: $dir_name"
      continue
    fi
    
    ((total_repos++))
    
    if [[ -d "$dir_name/.git" ]]; then
      (cd "$dir_name" && {
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null || [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
          local unstaged=$(git diff --name-only 2>/dev/null | wc -l)
          local staged=$(git diff --cached --name-only 2>/dev/null | wc -l)
          local untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l)
          print_success "Would update: $dir_name (Unstaged: $unstaged, Staged: $staged, Untracked: $untracked)"
          ((repos_with_changes++))
        else
          print_status "Would skip: $dir_name (no changes)"
        fi
      })
    else
      print_warning "Would skip: $dir_name (not a git repository)"
    fi
  done
  
  echo ""
  print_status "Dry run summary:"
  echo "  Total repositories checked: $total_repos"
  echo "  Repositories with changes: $repos_with_changes"
  echo "  Repositories that would be updated: $repos_with_changes"
}

# Function to detect if --no-verify should be used for git commit
should_use_no_verify() {
  local repo_dir="$1"
  
  # Check for template variables containing "password" in staged files
  if git diff --cached --name-only 2>/dev/null | xargs -I {} grep -l "{{.*password.*}}" {} 2>/dev/null | head -1 >/dev/null; then
    return 0  # Use --no-verify
  fi
  
  # Check for "password" in README files that are staged
  if git diff --cached --name-only 2>/dev/null | grep -i "readme" | xargs -I {} grep -l "password" {} 2>/dev/null | head -1 >/dev/null; then
    return 0  # Use --no-verify
  fi
  
  # Check for Ansible/Jinja2 template variables in any staged files
  if git diff --cached --name-only 2>/dev/null | xargs -I {} grep -l "{{.*}}" {} 2>/dev/null | head -1 >/dev/null; then
    # If we find template variables, check if any contain common sensitive-looking keywords
    if git diff --cached --name-only 2>/dev/null | xargs -I {} grep -l "{{.*\(password\|secret\|key\|token\).*}}" {} 2>/dev/null | head -1 >/dev/null; then
      return 0  # Use --no-verify
    fi
  fi
  
  return 1  # Don't use --no-verify
}

# Function to execute auto-commit across repositories
execute_auto_commit() {
  local base_dir="$1"
  local commit_msg="$2"
  local gh_user="$3"
  local gh_token="$4"
  
  print_status "EXECUTING auto-commit and push"
  print_status "Base directory: $base_dir"
  print_status "Commit message: '$commit_msg'"
  echo ""
  
  # Configure git credentials temporarily
  git config --global credential.helper store
  echo "https://${gh_user}:${gh_token}@github.com" > ~/.git-credentials 2>/dev/null
  
  cd "$base_dir" || return 1
  
  local total_processed=0
  local total_succeeded=0
  local total_failed=0
  local total_skipped=0
  
  for dir in */; do
    dir_name="${dir%/}"
    
    # Check if directory should be excluded
    local excluded=false
    for excl in "${excluded_dirs[@]}"; do
      if [[ "$dir_name" == "$excl" ]]; then
        excluded=true
        break
      fi
    done
    
    if [[ "$excluded" == "true" ]]; then
      print_warning "Skipping excluded directory: $dir_name"
      continue
    fi
    
    ((total_processed++))
    echo ""
    print_status "Processing: $dir_name"
    
    if [[ -d "$dir_name/.git" ]]; then
      (cd "$dir_name" && {
        if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null || [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
          local status_summary=$(git status --porcelain | wc -l)
          print_status "Changes detected - $status_summary files to process"
          
          # Show sample changes
          if [[ $status_summary -gt 0 ]]; then
            git status --porcelain | head -3 | while IFS= read -r line; do
              echo "  $line"
            done
            [[ $status_summary -gt 3 ]] && echo "  ... and $((status_summary - 3)) more files"
          fi
          
          # Perform git operations
          if git add --all 2>/dev/null; then
            # Check if we should use --no-verify
            local commit_cmd="git commit -m \"$commit_msg\""
            if should_use_no_verify "$(pwd)"; then
              commit_cmd="git commit --no-verify -m \"$commit_msg\""
              print_status "Using --no-verify due to template variables or README passwords detected"
            fi
            
            if eval "$commit_cmd" 2>/dev/null && git push 2>/dev/null; then
              print_success "Successfully committed and pushed: $dir_name"
              return 0
            else
              print_error "Failed git operations for: $dir_name"
              return 1
            fi
          else
            print_error "Failed to add files for: $dir_name"
            return 1
          fi
        else
          print_status "No changes in: $dir_name"
          return 2
        fi
      })
      
      case $? in
        0) ((total_succeeded++)) ;;
        1) ((total_failed++)) ;;
        2) ((total_skipped++)) ;;
      esac
    else
      print_warning "Not a git repository: $dir_name"
      ((total_skipped++))
    fi
  done
  
  # Clean up credentials
  rm -f ~/.git-credentials
  git config --global --unset credential.helper 2>/dev/null || true
  
  # Display summary
  echo ""
  echo "=========================================="
  print_status "AUTO-COMMIT SUMMARY"
  echo "=========================================="
  echo "Repositories processed: $total_processed"
  echo "Successfully updated: $total_succeeded"
  echo "Failed to update: $total_failed"
  echo "Skipped (no changes/not git): $total_skipped"
  echo ""
  
  if [[ $total_failed -eq 0 ]]; then
    print_success "All repositories processed successfully!"
    return 0
  else
    print_warning "Some repositories failed to update. Check the output above for details."
    return 1
  fi
}

# Function to protect repository with branch protection rules
protect_repository() {
  echo ""
  echo "=========================================="
  echo " Repository Protection Setup"
  echo "=========================================="
  echo ""
  
  read -p "Enter GitHub username/organization: " gh_user
  if [[ -z "$gh_user" ]]; then
    print_error "Username/organization cannot be empty"
    return 1
  fi
  
  read -p "Enter repository name: " repo_name
  if [[ -z "$repo_name" ]]; then
    print_error "Repository name cannot be empty"
    return 1
  fi
  
  read -p "Enter GitHub domain (press Enter for github.com): " github_url
  if [[ -z "$github_url" ]]; then
    github_url="github.com"
    api_url="https://api.github.com"
  else
    # Clean up domain input
    github_url=${github_url#https://}
    github_url=${github_url#http://}
    github_url=${github_url%/}
  fi
  
  read -p "Enter branch to protect (default: main): " branch_name
  branch_name=${branch_name:-"main"}
  
  echo ""
  print_status "GitHub Token Required (needs 'repo' scope with admin permissions)"
  read -s -p "Enter your GitHub Personal Access Token: " gh_token
  echo ""
  
  if [[ -z "$gh_token" ]]; then
    print_error "GitHub token cannot be empty"
    return 1
  fi
  
  echo ""
  print_status "Protection Configuration Options:"
  echo "1) Basic Protection (Require pull requests, dismiss stale reviews)"
  echo "2) Advanced Protection (+ Require status checks, restrict pushes)"
  echo "3) Maximum Protection (+ Require admin reviews, lock branch)"
  echo "4) Custom Configuration"
  read -p "Choose protection level (1-4): " protection_level
  
  case $protection_level in
    1) setup_basic_protection "$api_url" "$gh_user" "$repo_name" "$branch_name" "$gh_token" ;;
    2) setup_advanced_protection "$api_url" "$gh_user" "$repo_name" "$branch_name" "$gh_token" ;;
    3) setup_maximum_protection "$api_url" "$gh_user" "$repo_name" "$branch_name" "$gh_token" ;;
    4) setup_custom_protection "$api_url" "$gh_user" "$repo_name" "$branch_name" "$gh_token" ;;
    *) print_error "Invalid choice"; return 1 ;;
  esac
}

# Function to setup basic protection
setup_basic_protection() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local branch_name="$4"
  local gh_token="$5"
  
  print_status "Setting up basic branch protection..."
  
  local protection_config='{
    "required_status_checks": null,
    "enforce_admins": false,
    "required_pull_request_reviews": {
      "required_approving_review_count": 1,
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": false,
      "require_last_push_approval": false
    },
    "restrictions": null,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "block_creations": false,
    "required_conversation_resolution": true
  }'
  
  apply_protection "$api_url" "$gh_user" "$repo_name" "$branch_name" "$gh_token" "$protection_config"
}

# Function to setup advanced protection
setup_advanced_protection() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local branch_name="$4"
  local gh_token="$5"
  
  print_status "Setting up advanced branch protection..."
  
  local protection_config='{
    "required_status_checks": {
      "strict": true,
      "contexts": []
    },
    "enforce_admins": false,
    "required_pull_request_reviews": {
      "required_approving_review_count": 2,
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": true,
      "require_last_push_approval": true
    },
    "restrictions": {
      "users": [],
      "teams": [],
      "apps": []
    },
    "allow_force_pushes": false,
    "allow_deletions": false,
    "block_creations": false,
    "required_conversation_resolution": true
  }'
  
  apply_protection "$api_url" "$gh_user" "$repo_name" "$branch_name" "$gh_token" "$protection_config"
}

# Function to setup maximum protection
setup_maximum_protection() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local branch_name="$4"
  local gh_token="$5"
  
  print_status "Setting up maximum branch protection..."
  
  local protection_config='{
    "required_status_checks": {
      "strict": true,
      "contexts": []
    },
    "enforce_admins": true,
    "required_pull_request_reviews": {
      "required_approving_review_count": 2,
      "dismiss_stale_reviews": true,
      "require_code_owner_reviews": true,
      "require_last_push_approval": true
    },
    "restrictions": {
      "users": [],
      "teams": [],
      "apps": []
    },
    "allow_force_pushes": false,
    "allow_deletions": false,
    "block_creations": true,
    "required_conversation_resolution": true
  }'
  
  apply_protection "$api_url" "$gh_user" "$repo_name" "$branch_name" "$gh_token" "$protection_config"
}

# Function to setup custom protection
setup_custom_protection() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local branch_name="$4"
  local gh_token="$5"
  
  print_status "Setting up custom branch protection..."
  echo ""
  
  # Required pull request reviews
  read -p "Require pull request reviews? (y/N): " require_pr
  if [[ "$require_pr" =~ ^[Yy]$ ]]; then
    read -p "Number of required approving reviews (1-6) [1]: " review_count
    review_count=${review_count:-1}
    
    read -p "Dismiss stale reviews when new commits are pushed? (Y/n): " dismiss_stale
    dismiss_stale=${dismiss_stale:-Y}
    
    read -p "Require review from code owners? (y/N): " require_code_owners
    read -p "Require approval of the most recent push? (y/N): " require_last_push
    
    pr_reviews='"required_pull_request_reviews": {
      "required_approving_review_count": '$review_count',
      "dismiss_stale_reviews": '$([ "$dismiss_stale" = "Y" ] && echo "true" || echo "false")',
      "require_code_owner_reviews": '$([ "$require_code_owners" = "y" ] && echo "true" || echo "false")',
      "require_last_push_approval": '$([ "$require_last_push" = "y" ] && echo "true" || echo "false")'
    }'
  else
    pr_reviews='"required_pull_request_reviews": null'
  fi
  
  # Status checks
  read -p "Require status checks to pass? (y/N): " require_status
  if [[ "$require_status" =~ ^[Yy]$ ]]; then
    read -p "Require branches to be up to date before merging? (Y/n): " require_strict
    require_strict=${require_strict:-Y}
    
    status_checks='"required_status_checks": {
      "strict": '$([ "$require_strict" = "Y" ] && echo "true" || echo "false")',
      "contexts": []
    }'
  else
    status_checks='"required_status_checks": null'
  fi
  
  # Admin enforcement
  read -p "Enforce restrictions for administrators? (y/N): " enforce_admins
  enforce_admins=$([ "$enforce_admins" = "y" ] && echo "true" || echo "false")
  
  # Other settings
  read -p "Allow force pushes? (y/N): " allow_force
  allow_force=$([ "$allow_force" = "y" ] && echo "true" || echo "false")
  
  read -p "Allow deletions? (y/N): " allow_deletions
  allow_deletions=$([ "$allow_deletions" = "y" ] && echo "true" || echo "false")
  
  read -p "Require conversation resolution before merging? (Y/n): " require_conversation
  require_conversation=${require_conversation:-Y}
  require_conversation=$([ "$require_conversation" = "Y" ] && echo "true" || echo "false")
  
  local protection_config='{
    '$status_checks',
    "enforce_admins": '$enforce_admins',
    '$pr_reviews',
    "restrictions": null,
    "allow_force_pushes": '$allow_force',
    "allow_deletions": '$allow_deletions',
    "block_creations": false,
    "required_conversation_resolution": '$require_conversation'
  }'
  
  apply_protection "$api_url" "$gh_user" "$repo_name" "$branch_name" "$gh_token" "$protection_config"
}

# Function to apply protection configuration
apply_protection() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local branch_name="$4"
  local gh_token="$5"
  local protection_config="$6"
  
  print_status "Applying branch protection to $gh_user/$repo_name:$branch_name..."
  
  # Apply branch protection
  local http_response=$(curl -s -w "%{http_code}" \
    -X PUT \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    "$api_url/repos/$gh_user/$repo_name/branches/$branch_name/protection" \
    -d "$protection_config" \
    -o /tmp/github_protection_response.json)
  
  if [[ "$http_response" == "200" ]]; then
    print_success "Branch protection successfully applied!"
    echo ""
    print_status "Protection Summary:"
    
    # Parse and display the applied settings
    if command -v jq >/dev/null 2>&1; then
      echo "  Repository: $gh_user/$repo_name"
      echo "  Protected Branch: $branch_name"
      echo "  URL: https://$github_url/$gh_user/$repo_name/settings/branch_protection_rules"
      echo ""
      
      local pr_required=$(jq -r '.required_pull_request_reviews // empty' /tmp/github_protection_response.json)
      if [[ "$pr_required" != "" && "$pr_required" != "null" ]]; then
        local review_count=$(jq -r '.required_pull_request_reviews.required_approving_review_count' /tmp/github_protection_response.json)
        echo "  [ENABLED] Pull Request Reviews: Required ($review_count approvals needed)"
      else
        echo "  [WARNING] Pull Request Reviews: Not required"
      fi
      
      local status_checks=$(jq -r '.required_status_checks // empty' /tmp/github_protection_response.json)
      if [[ "$status_checks" != "" && "$status_checks" != "null" ]]; then
        echo "  [ENABLED] Status Checks: Required"
      else
        echo "  [WARNING] Status Checks: Not required"
      fi
      
      local enforce_admins=$(jq -r '.enforce_admins.enabled' /tmp/github_protection_response.json)
      if [[ "$enforce_admins" == "true" ]]; then
        echo "  [ENABLED] Admin Enforcement: Enabled"
      else
        echo "  [WARNING] Admin Enforcement: Disabled"
      fi
      
    else
      echo "  Repository: $gh_user/$repo_name"
      echo "  Protected Branch: $branch_name"
      echo "  View settings: https://$github_url/$gh_user/$repo_name/settings/branch_protection_rules"
    fi
    
  elif [[ "$http_response" == "403" ]]; then
    print_error "Access denied. Make sure your token has admin permissions for this repository."
    if [[ -f /tmp/github_protection_response.json ]]; then
      echo "Response details:"
      cat /tmp/github_protection_response.json
    fi
  elif [[ "$http_response" == "404" ]]; then
    print_error "Repository or branch not found: $gh_user/$repo_name:$branch_name"
    print_error "Make sure the repository exists and the branch name is correct."
  else
    print_error "Failed to apply branch protection (HTTP: $http_response)"
    if [[ -f /tmp/github_protection_response.json ]]; then
      echo "Response details:"
      cat /tmp/github_protection_response.json
    fi
  fi
  
  rm -f /tmp/github_protection_response.json
  
  echo ""
  echo "=========================================="
  print_success "Repository protection setup completed!"
  echo "=========================================="
}

# Function to manage pull requests (accept and merge)
manage_pull_requests() {
  echo ""
  echo "=========================================="
  echo " Pull Request Management"
  echo "=========================================="
  echo ""
  
  read -p "Enter GitHub username/organization: " gh_user
  if [[ -z "$gh_user" ]]; then
    print_error "Username/organization cannot be empty"
    return 1
  fi
  
  read -p "Enter repository name: " repo_name
  if [[ -z "$repo_name" ]]; then
    print_error "Repository name cannot be empty"
    return 1
  fi
  
  read -p "Enter GitHub domain (press Enter for github.com): " github_url
  if [[ -z "$github_url" ]]; then
    github_url="github.com"
    api_url="https://api.github.com"
  else
    # Clean up domain input
    github_url=${github_url#https://}
    github_url=${github_url#http://}
    github_url=${github_url%/}
  fi
  
  echo ""
  print_status "GitHub Token Required (needs 'repo' scope)"
  read -s -p "Enter your GitHub Personal Access Token: " gh_token
  echo ""
  
  if [[ -z "$gh_token" ]]; then
    print_error "GitHub token cannot be empty"
    return 1
  fi
  
  echo ""
  print_status "Pull Request Actions:"
  echo "1) List open pull requests"
  echo "2) Review and merge a specific pull request"
  echo "3) Close a pull request without merging"
  echo "4) Get pull request details"
  read -p "Choose action (1-4): " pr_action
  
  case $pr_action in
    1) list_pull_requests "$api_url" "$gh_user" "$repo_name" "$gh_token" ;;
    2) merge_pull_request "$api_url" "$gh_user" "$repo_name" "$gh_token" "$github_url" ;;
    3) close_pull_request "$api_url" "$gh_user" "$repo_name" "$gh_token" ;;
    4) get_pr_details "$api_url" "$gh_user" "$repo_name" "$gh_token" ;;
    *) print_error "Invalid choice"; return 1 ;;
  esac
}

# Function to list open pull requests
list_pull_requests() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local gh_token="$4"
  
  print_status "Fetching open pull requests for $gh_user/$repo_name..."
  
  local http_response=$(curl -s -w "%{http_code}" \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    "$api_url/repos/$gh_user/$repo_name/pulls?state=open" \
    -o /tmp/github_prs_response.json)
  
  if [[ "$http_response" == "200" ]]; then
    local pr_count=$(jq length /tmp/github_prs_response.json 2>/dev/null || echo "0")
    
    if [[ "$pr_count" == "0" ]]; then
      print_warning "No open pull requests found"
      return 0
    fi
    
    echo ""
    print_success "Found $pr_count open pull request(s):"
    echo ""
    
    if command -v jq >/dev/null 2>&1; then
      jq -r '.[] | "PR #\(.number): \(.title)\n  Author: \(.user.login)\n  Branch: \(.head.ref) -> \(.base.ref)\n  Created: \(.created_at)\n  URL: \(.html_url)\n"' /tmp/github_prs_response.json
    else
      print_warning "jq not installed. Showing raw response:"
      cat /tmp/github_prs_response.json
    fi
  else
    print_error "Failed to fetch pull requests (HTTP: $http_response)"
    if [[ -f /tmp/github_prs_response.json ]]; then
      cat /tmp/github_prs_response.json
    fi
  fi
  
  rm -f /tmp/github_prs_response.json
}

# Function to get pull request details
get_pr_details() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local gh_token="$4"
  
  read -p "Enter pull request number: " pr_number
  if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    print_error "Invalid pull request number"
    return 1
  fi
  
  print_status "Fetching details for PR #$pr_number..."
  
  local http_response=$(curl -s -w "%{http_code}" \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    "$api_url/repos/$gh_user/$repo_name/pulls/$pr_number" \
    -o /tmp/github_pr_details.json)
  
  if [[ "$http_response" == "200" ]]; then
    echo ""
    print_success "Pull Request #$pr_number Details:"
    echo ""
    
    if command -v jq >/dev/null 2>&1; then
      echo "Title: $(jq -r '.title' /tmp/github_pr_details.json)"
      echo "Author: $(jq -r '.user.login' /tmp/github_pr_details.json)"
      echo "State: $(jq -r '.state' /tmp/github_pr_details.json)"
      echo "Branch: $(jq -r '.head.ref' /tmp/github_pr_details.json) -> $(jq -r '.base.ref' /tmp/github_pr_details.json)"
      echo "Created: $(jq -r '.created_at' /tmp/github_pr_details.json)"
      echo "Updated: $(jq -r '.updated_at' /tmp/github_pr_details.json)"
      echo "Mergeable: $(jq -r '.mergeable // "unknown"' /tmp/github_pr_details.json)"
      echo "Commits: $(jq -r '.commits' /tmp/github_pr_details.json)"
      echo "Additions: +$(jq -r '.additions' /tmp/github_pr_details.json)"
      echo "Deletions: -$(jq -r '.deletions' /tmp/github_pr_details.json)"
      echo "Changed Files: $(jq -r '.changed_files' /tmp/github_pr_details.json)"
      echo ""
      echo "Description:"
      jq -r '.body // "No description provided"' /tmp/github_pr_details.json
      echo ""
      echo "URL: $(jq -r '.html_url' /tmp/github_pr_details.json)"
    else
      print_warning "jq not installed. Showing raw response:"
      cat /tmp/github_pr_details.json
    fi
  else
    print_error "Failed to fetch PR details (HTTP: $http_response)"
    if [[ -f /tmp/github_pr_details.json ]]; then
      cat /tmp/github_pr_details.json
    fi
  fi
  
  rm -f /tmp/github_pr_details.json
}

# Function to merge a pull request
merge_pull_request() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local gh_token="$4"
  local github_url="$5"
  
  # First, list open PRs for reference
  list_pull_requests "$api_url" "$gh_user" "$repo_name" "$gh_token"
  
  echo ""
  read -p "Enter pull request number to merge: " pr_number
  if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    print_error "Invalid pull request number"
    return 1
  fi
  
  # Get PR details first
  print_status "Checking PR #$pr_number status..."
  local http_response=$(curl -s -w "%{http_code}" \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    "$api_url/repos/$gh_user/$repo_name/pulls/$pr_number" \
    -o /tmp/github_pr_check.json)
  
  if [[ "$http_response" != "200" ]]; then
    print_error "Pull request #$pr_number not found"
    rm -f /tmp/github_pr_check.json
    return 1
  fi
  
  local pr_state=$(jq -r '.state' /tmp/github_pr_check.json 2>/dev/null || echo "unknown")
  local pr_title=$(jq -r '.title' /tmp/github_pr_check.json 2>/dev/null || echo "unknown")
  local pr_author=$(jq -r '.user.login' /tmp/github_pr_check.json 2>/dev/null || echo "unknown")
  local pr_mergeable=$(jq -r '.mergeable // "unknown"' /tmp/github_pr_check.json 2>/dev/null)
  local pr_branch=$(jq -r '.head.ref' /tmp/github_pr_check.json 2>/dev/null || echo "unknown")
  
  if [[ "$pr_state" != "open" ]]; then
    print_error "Pull request #$pr_number is not open (state: $pr_state)"
    rm -f /tmp/github_pr_check.json
    return 1
  fi
  
  echo ""
  print_status "Pull Request Summary:"
  echo "  PR #$pr_number: $pr_title"
  echo "  Author: $pr_author"
  echo "  Branch: $pr_branch"
  echo "  Mergeable: $pr_mergeable"
  echo ""
  
  if [[ "$pr_mergeable" == "false" ]]; then
    print_warning "This PR has merge conflicts that must be resolved first"
    read -p "Do you want to continue anyway? (y/N): " continue_anyway
    if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
      print_status "Merge cancelled"
      rm -f /tmp/github_pr_check.json
      return 0
    fi
  fi
  
  # Choose merge method
  echo "Merge method options:"
  echo "1) Merge commit (preserves branch history)"
  echo "2) Squash and merge (combines commits into one)"
  echo "3) Rebase and merge (replays commits without merge commit)"
  read -p "Choose merge method (1-3) [1]: " merge_method_choice
  merge_method_choice=${merge_method_choice:-1}
  
  case $merge_method_choice in
    1) merge_method="merge" ;;
    2) merge_method="squash" ;;
    3) merge_method="rebase" ;;
    *) print_error "Invalid choice"; rm -f /tmp/github_pr_check.json; return 1 ;;
  esac
  
  # Get commit message
  read -p "Enter commit message (press Enter for default): " commit_message
  if [[ -z "$commit_message" ]]; then
    case $merge_method in
      "merge") commit_message="Merge pull request #$pr_number from $pr_branch" ;;
      "squash") commit_message="$pr_title (#$pr_number)" ;;
      "rebase") commit_message="" ;;  # Rebase uses original commit messages
    esac
  fi
  
  # Final confirmation
  echo ""
  print_warning "Ready to merge PR #$pr_number using $merge_method method"
  read -p "Are you sure you want to proceed? (y/N): " confirm_merge
  if [[ ! "$confirm_merge" =~ ^[Yy]$ ]]; then
    print_status "Merge cancelled"
    rm -f /tmp/github_pr_check.json
    return 0
  fi
  
  # Prepare merge request
  local merge_data='{"commit_title":"'"$commit_message"'","commit_message":"","merge_method":"'"$merge_method"'"}'
  
  # Perform the merge
  print_status "Merging PR #$pr_number..."
  local merge_response=$(curl -s -w "%{http_code}" \
    -X PUT \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    "$api_url/repos/$gh_user/$repo_name/pulls/$pr_number/merge" \
    -d "$merge_data" \
    -o /tmp/github_merge_response.json)
  
  if [[ "$merge_response" == "200" ]]; then
    local merge_sha=$(jq -r '.sha' /tmp/github_merge_response.json 2>/dev/null || echo "unknown")
    print_success "Pull request #$pr_number successfully merged!"
    echo "  Merge commit SHA: $merge_sha"
    echo "  Method: $merge_method"
    echo "  View: https://$github_url/$gh_user/$repo_name/pull/$pr_number"
    
    # Ask about deleting the branch
    echo ""
    read -p "Delete the source branch '$pr_branch'? (y/N): " delete_branch
    if [[ "$delete_branch" =~ ^[Yy]$ ]]; then
      delete_merged_branch "$api_url" "$gh_user" "$repo_name" "$pr_branch" "$gh_token"
    fi
    
  elif [[ "$merge_response" == "405" ]]; then
    print_error "Pull request cannot be merged (may have conflicts or restrictions)"
    if [[ -f /tmp/github_merge_response.json ]]; then
      local error_msg=$(jq -r '.message // "Unknown error"' /tmp/github_merge_response.json 2>/dev/null)
      echo "Error: $error_msg"
    fi
  elif [[ "$merge_response" == "409" ]]; then
    print_error "Pull request has conflicts that must be resolved first"
  else
    print_error "Failed to merge pull request (HTTP: $merge_response)"
    if [[ -f /tmp/github_merge_response.json ]]; then
      cat /tmp/github_merge_response.json
    fi
  fi
  
  rm -f /tmp/github_pr_check.json /tmp/github_merge_response.json
}

# Function to close a pull request without merging
close_pull_request() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local gh_token="$4"
  
  # First, list open PRs for reference
  list_pull_requests "$api_url" "$gh_user" "$repo_name" "$gh_token"
  
  echo ""
  read -p "Enter pull request number to close: " pr_number
  if [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    print_error "Invalid pull request number"
    return 1
  fi
  
  read -p "Enter reason for closing (optional): " close_reason
  
  echo ""
  print_warning "This will close PR #$pr_number without merging"
  read -p "Are you sure? (y/N): " confirm_close
  if [[ ! "$confirm_close" =~ ^[Yy]$ ]]; then
    print_status "Close cancelled"
    return 0
  fi
  
  # Close the PR
  local close_data='{"state":"closed"}'
  local close_response=$(curl -s -w "%{http_code}" \
    -X PATCH \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    "$api_url/repos/$gh_user/$repo_name/pulls/$pr_number" \
    -d "$close_data" \
    -o /tmp/github_close_response.json)
  
  if [[ "$close_response" == "200" ]]; then
    print_success "Pull request #$pr_number has been closed"
    
    # Add a comment if reason was provided
    if [[ -n "$close_reason" ]]; then
      local comment_data='{"body":"Closed: '"$close_reason"'"}'
      curl -s \
        -X POST \
        -H "Authorization: token $gh_token" \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Content-Type: application/json" \
        "$api_url/repos/$gh_user/$repo_name/issues/$pr_number/comments" \
        -d "$comment_data" >/dev/null
      print_status "Added closing comment"
    fi
  else
    print_error "Failed to close pull request (HTTP: $close_response)"
    if [[ -f /tmp/github_close_response.json ]]; then
      cat /tmp/github_close_response.json
    fi
  fi
  
  rm -f /tmp/github_close_response.json
}

# Function to delete a merged branch
delete_merged_branch() {
  local api_url="$1"
  local gh_user="$2"
  local repo_name="$3"
  local branch_name="$4"
  local gh_token="$5"
  
  print_status "Deleting branch '$branch_name'..."
  
  local delete_response=$(curl -s -w "%{http_code}" \
    -X DELETE \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    "$api_url/repos/$gh_user/$repo_name/git/refs/heads/$branch_name" \
    -o /tmp/github_delete_branch.json)
  
  if [[ "$delete_response" == "204" ]]; then
    print_success "Branch '$branch_name' has been deleted"
  elif [[ "$delete_response" == "422" ]]; then
    print_warning "Branch '$branch_name' could not be deleted (may be protected or default branch)"
  else
    print_error "Failed to delete branch '$branch_name' (HTTP: $delete_response)"
  fi
  
  rm -f /tmp/github_delete_branch.json
}

# Function to manage repository secrets (uses GitHub CLI if available; falls back to API for list/delete)
manage_repository_secrets() {
  echo ""
  echo "=========================================="
  echo " Repository Secrets Management"
  echo "=========================================="
  echo ""

  read -p "Enter GitHub username/organization: " gh_user
  if [[ -z "$gh_user" ]]; then
    print_error "Username/organization cannot be empty"
    return 1
  fi

  read -p "Enter repository name: " repo_name
  if [[ -z "$repo_name" ]]; then
    print_error "Repository name cannot be empty"
    return 1
  fi

  read -p "Enter GitHub domain (press Enter for github.com): " github_url
  if [[ -z "$github_url" ]]; then
    github_url="github.com"
    api_url="https://api.github.com"
  else
    # Clean up domain input
    github_url=${github_url#https://}
    github_url=${github_url#http://}
    github_url=${github_url%/}

    if [[ "$github_url" == "github.com" ]]; then
      api_url="https://api.github.com"
    else
      api_url="https://$github_url/api/v3"
    fi
  fi

  local use_gh_cli=false
  if command -v gh >/dev/null 2>&1; then
    use_gh_cli=true
  fi

  # Obtain token only if needed for API fallback
  local gh_token=""
  if [[ "$use_gh_cli" != true ]]; then
    gh_token=$(secure_get_token)
    if [[ -z "$gh_token" ]]; then
      print_error "A GitHub token is required when GitHub CLI is not available"
      return 1
    fi
  fi

  while true; do
    echo ""
    print_status "Secrets actions for $gh_user/$repo_name:"
    echo "1) List repository secrets"
    echo "2) Create/Update a secret"
    echo "3) Delete a secret"
    echo "4) Back"
    read -p "Choose action (1-4): " secrets_action

    case $secrets_action in
      1)
        print_status "Listing secrets..."
        if [[ "$use_gh_cli" == true ]]; then
          gh secret list -R "$gh_user/$repo_name" || print_warning "Failed to list secrets via gh"
        else
          # REST API: List secrets
          local http_response=$(curl -s -w "%{http_code}" \
            -H "Authorization: token $gh_token" \
            -H "Accept: application/vnd.github.v3+json" \
            "$api_url/repos/$gh_user/$repo_name/actions/secrets" \
            -o /tmp/github_secrets_list.json)
          if [[ "$http_response" == "200" ]]; then
            if command -v jq >/dev/null 2>&1; then
              jq -r '.secrets[]? | "- \(.name) (updated: \(.updated_at))"' /tmp/github_secrets_list.json || echo "No secrets found"
            else
              grep -o '"name":"[^"]\+"' /tmp/github_secrets_list.json | cut -d'"' -f4 | sed 's/^/- /' || echo "No secrets found"
            fi
          else
            print_error "Failed to list secrets (HTTP: $http_response)"
            [[ -f /tmp/github_secrets_list.json ]] && cat /tmp/github_secrets_list.json
          fi
          rm -f /tmp/github_secrets_list.json
        fi
        ;;
      2)
        if [[ "$use_gh_cli" != true ]]; then
          print_error "Creating/updating secrets requires GitHub CLI (gh). Please install gh and run again."
          print_status "See: https://cli.github.com/"
          continue
        fi
        read -p "Enter secret name (e.g., MY_TOKEN): " secret_name
        if [[ -z "$secret_name" ]]; then
          print_error "Secret name cannot be empty"
          continue
        fi
        read -s -p "Enter secret value: " secret_value
        echo ""
        if [[ -z "$secret_value" ]]; then
          print_error "Secret value cannot be empty"
          continue
        fi
        print_status "Setting secret $secret_name in $gh_user/$repo_name..."
        if echo -n "$secret_value" | gh secret set "$secret_name" -R "$gh_user/$repo_name" -b-; then
          print_success "Secret '$secret_name' set successfully"
        else
          print_error "Failed to set secret '$secret_name'"
        fi
        ;;
      3)
        read -p "Enter secret name to delete: " secret_name
        if [[ -z "$secret_name" ]]; then
          print_error "Secret name cannot be empty"
          continue
        fi
        read -p "Are you sure you want to delete '$secret_name'? (y/N): " confirm_del
        if [[ ! "$confirm_del" =~ ^[Yy]$ ]]; then
          print_status "Deletion cancelled"
          continue
        fi
        if [[ "$use_gh_cli" == true ]]; then
          if gh secret delete "$secret_name" -R "$gh_user/$repo_name" -y; then
            print_success "Secret '$secret_name' deleted"
          else
            print_error "Failed to delete secret '$secret_name' via gh"
          fi
        else
          # REST API: Delete secret
          local del_response=$(curl -s -w "%{http_code}" \
            -X DELETE \
            -H "Authorization: token $gh_token" \
            -H "Accept: application/vnd.github.v3+json" \
            "$api_url/repos/$gh_user/$repo_name/actions/secrets/$secret_name" \
            -o /tmp/github_secret_delete.json)
          if [[ "$del_response" == "204" ]]; then
            print_success "Secret '$secret_name' deleted"
          elif [[ "$del_response" == "404" ]]; then
            print_warning "Secret '$secret_name' not found"
          else
            print_error "Failed to delete secret '$secret_name' (HTTP: $del_response)"
            [[ -f /tmp/github_secret_delete.json ]] && cat /tmp/github_secret_delete.json
          fi
          rm -f /tmp/github_secret_delete.json
        fi
        ;;
      4)
        return 0
        ;;
      *)
        print_error "Invalid choice"
        ;;
    esac
  done
}

# Function to cleanup repository for General Availability (GA)
cleanup_repository_for_ga() {
  echo ""
  echo "=========================================="
  echo " Repository GA Cleanup & Backup"
  echo "=========================================="
  echo ""
  print_warning "This will clean up your repository for General Availability"
  print_warning "A backup will be created before any changes are made"
  echo ""
  
  read -p "Enter the path to the repository to cleanup: " repo_path
  if [[ -z "$repo_path" ]]; then
    print_error "Repository path cannot be empty"
    return 1
  fi
  
  # Convert to absolute path
  repo_path=$(realpath "$repo_path" 2>/dev/null)
  if [[ ! -d "$repo_path" ]]; then
    print_error "Repository path does not exist: $repo_path"
    return 1
  fi
  
  if [[ ! -d "$repo_path/.git" ]]; then
    print_error "Not a git repository: $repo_path"
    return 1
  fi
  
  local repo_name=$(basename "$repo_path")
  local backup_dir="$HOME/backup"
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local backup_name="${repo_name}_backup_${timestamp}.tar.gz"
  
  echo ""
  print_status "Repository: $repo_path"
  print_status "Backup will be saved to: $backup_dir/$backup_name"
  echo ""
  
  read -p "Do you want to proceed with cleanup? (y/N): " confirm
  confirm=${confirm:-n}
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_status "Cleanup cancelled"
    return 0
  fi
  
  # Create backup directory
  mkdir -p "$backup_dir"
  if [[ $? -ne 0 ]]; then
    print_error "Failed to create backup directory: $backup_dir"
    return 1
  fi
  
  # Create backup
  print_status "Creating backup archive..."
  cd "$(dirname "$repo_path")"
  tar -czf "$backup_dir/$backup_name" "$(basename "$repo_path")" 2>/dev/null
  if [[ $? -eq 0 ]]; then
    local backup_size=$(du -h "$backup_dir/$backup_name" | cut -f1)
    print_success "Backup created: $backup_name ($backup_size)"
  else
    print_error "Failed to create backup archive"
    return 1
  fi
  
  # Now perform cleanup
  cd "$repo_path"
  
  echo ""
  print_status "Starting repository cleanup process..."
  
  # 1. Check for and remove common unnecessary files
  cleanup_unnecessary_files "$repo_path"
  
  # 2. Check file syntax
  check_file_syntax "$repo_path"
  
  # 3. Clean git history
  read -p "Do you want to clean git history (remove all commits and start fresh)? (y/N): " clean_history
  clean_history=${clean_history:-n}
  if [[ "$clean_history" =~ ^[Yy]$ ]]; then
    clean_git_history "$repo_path"
  fi
  
  # 4. Optimize repository
  optimize_repository "$repo_path"
  
  echo ""
  print_success "Repository cleanup completed!"
  print_status "Backup saved: $backup_dir/$backup_name"
  echo ""
}

# Function to cleanup unnecessary files
cleanup_unnecessary_files() {
  local repo_path="$1"
  
  print_status "Cleaning up unnecessary files..."
  
  cd "$repo_path"
  
  # Define patterns for files to remove
  local cleanup_patterns=(
    "*.log"
    "*.tmp"
    "*.temp"
    "*.bak"
    "*.backup"
    "*.old"
    "*~"
    ".DS_Store"
    "Thumbs.db"
    "*.swp"
    "*.swo"
    ".*.swp"
    ".*.swo"
    "*.pyc"
    "*.pyo"
    "__pycache__"
    ".pytest_cache"
    "*.egg-info"
    "build/"
    "dist/"
    ".coverage"
    ".nyc_output"
    "node_modules/"
    "npm-debug.log*"
    "yarn-debug.log*"
    "yarn-error.log*"
    ".env.local"
    ".env.development.local"
    ".env.test.local"
    ".env.production.local"
    "*.secret"
    "*.key"
    "*.pem"
    ".vscode/settings.json"
    ".idea/"
  )
  
  local files_removed=0
  local total_size_saved=0
  
  for pattern in "${cleanup_patterns[@]}"; do
    while IFS= read -r -d '' file; do
      if [[ -f "$file" || -d "$file" ]]; then
        local file_size
        if [[ -f "$file" ]]; then
          file_size=$(du -b "$file" 2>/dev/null | cut -f1)
        else
          file_size=$(du -sb "$file" 2>/dev/null | cut -f1)
        fi
        total_size_saved=$((total_size_saved + file_size))
        rm -rf "$file"
        files_removed=$((files_removed + 1))
        echo "  Removed: $file"
      fi
    done < <(find . -name "$pattern" -print0 2>/dev/null)
  done
  
  # Look for large files that might be unnecessary
  print_status "Checking for large files (>10MB)..."
  while IFS= read -r -d '' file; do
    local file_size_mb=$(du -m "$file" 2>/dev/null | cut -f1)
    if [[ $file_size_mb -gt 10 ]]; then
      print_warning "Large file found: $file (${file_size_mb}MB)"
      read -p "Remove this file? (y/N): " remove_large
      if [[ "$remove_large" =~ ^[Yy]$ ]]; then
        rm -f "$file"
        files_removed=$((files_removed + 1))
        total_size_saved=$((total_size_saved + file_size_mb * 1024 * 1024))
        echo "  Removed: $file"
      fi
    fi
  done < <(find . -type f -size +10M -print0 2>/dev/null | grep -v ".git")
  
  local size_saved_mb=$((total_size_saved / 1024 / 1024))
  print_success "Cleanup complete: $files_removed files removed, ${size_saved_mb}MB saved"
}

# Function to check file syntax
check_file_syntax() {
  local repo_path="$1"
  
  print_status "Checking file syntax..."
  
  cd "$repo_path"
  
  local syntax_errors=0
  local files_checked=0
  
  # Check Python files
  while IFS= read -r -d '' file; do
    files_checked=$((files_checked + 1))
    if ! python3 -m py_compile "$file" &>/dev/null; then
      print_error "Python syntax error in: $file"
      python3 -m py_compile "$file"
      syntax_errors=$((syntax_errors + 1))
    fi
  done < <(find . -name "*.py" -print0 2>/dev/null | grep -v ".git")
  
  # Check Shell scripts
  while IFS= read -r -d '' file; do
    files_checked=$((files_checked + 1))
    if ! bash -n "$file" 2>/dev/null; then
      print_error "Shell syntax error in: $file"
      bash -n "$file"
      syntax_errors=$((syntax_errors + 1))
    fi
  done < <(find . -name "*.sh" -print0 2>/dev/null | grep -v ".git")
  
  # Check YAML files
  if command -v yamllint >/dev/null 2>&1; then
    while IFS= read -r -d '' file; do
      files_checked=$((files_checked + 1))
      if ! yamllint "$file" >/dev/null 2>&1; then
        print_error "YAML syntax error in: $file"
        yamllint "$file"
        syntax_errors=$((syntax_errors + 1))
      fi
    done < <(find . \( -name "*.yml" -o -name "*.yaml" \) -print0 2>/dev/null | grep -v ".git")
  else
    print_warning "yamllint not installed, skipping YAML syntax checks"
  fi
  
  # Check JSON files
  while IFS= read -r -d '' file; do
    files_checked=$((files_checked + 1))
    if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
      print_error "JSON syntax error in: $file"
      python3 -m json.tool "$file"
      syntax_errors=$((syntax_errors + 1))
    fi
  done < <(find . -name "*.json" -print0 2>/dev/null | grep -v ".git")
  
  if [[ $syntax_errors -eq 0 ]]; then
    print_success "Syntax check complete: $files_checked files checked, no errors found"
  else
    print_warning "Syntax check complete: $files_checked files checked, $syntax_errors errors found"
    read -p "Continue with cleanup despite syntax errors? (y/N): " continue_cleanup
    if [[ ! "$continue_cleanup" =~ ^[Yy]$ ]]; then
      return 1
    fi
  fi
}

# Function to clean git history
clean_git_history() {
  local repo_path="$1"
  
  print_warning "This will remove ALL commit history and create a fresh initial commit"
  read -p "Are you absolutely sure? This cannot be undone! (y/N): " confirm_history
  if [[ ! "$confirm_history" =~ ^[Yy]$ ]]; then
    print_status "Git history cleanup skipped"
    return 0
  fi
  
  print_status "Cleaning git history..."
  
  cd "$repo_path"
  
  # Get current branch name
  local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
  
  # Remove .git directory and reinitialize
  rm -rf .git
  git init
  git branch -m "$current_branch"
  
  # Create .gitignore if it doesn't exist
  if [[ ! -f .gitignore ]]; then
    create_default_gitignore "$repo_path"
  fi
  
  # Add all files and create initial commit
  git add .
  local commit_cmd="git commit -m \"Initial commit - cleaned for GA release\""
  if should_use_no_verify "$(pwd)"; then
    commit_cmd="git commit --no-verify -m \"Initial commit - cleaned for GA release\""
    print_status "Using --no-verify due to template variables or README passwords detected"
  fi
  eval "$commit_cmd"
  
  print_success "Git history cleaned and reset with initial commit"
}

# Function to create a default .gitignore
create_default_gitignore() {
  local repo_path="$1"
  
  print_status "Creating default .gitignore..."
  
  cat > "$repo_path/.gitignore" << 'EOF'
# Logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*

# Runtime data
pids
*.pid
*.seed
*.pid.lock

# Coverage directory used by tools like istanbul
coverage/
.nyc_output

# Dependency directories
node_modules/
jspm_packages/

# Optional npm cache directory
.npm

# Optional REPL history
.node_repl_history

# Output of 'npm pack'
*.tgz

# Yarn Integrity file
.yarn-integrity

# dotenv environment variables file
.env
.env.local
.env.development.local
.env.test.local
.env.production.local

# Python
__pycache__/
*.py[cod]
*$py.class
*.so
.Python
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
wheels/
*.egg-info/
.installed.cfg
*.egg

# PyInstaller
*.manifest
*.spec

# Unit test / coverage reports
htmlcov/
.tox/
.coverage
.coverage.*
.cache
nosetests.xml
coverage.xml
*.cover
.hypothesis/
.pytest_cache/

# IDEs
.vscode/
.idea/
*.swp
*.swo
*~

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# Temporary files
*.tmp
*.temp
*.bak
*.backup
*.old

# Secrets
*.key
*.pem
*.secret
EOF

  print_success "Default .gitignore created"
}

# Function to optimize repository
optimize_repository() {
  local repo_path="$1"
  
  print_status "Optimizing repository..."
  
  cd "$repo_path"
  
  # Run git maintenance commands
  git gc --prune=now --aggressive 2>/dev/null
  git repack -ad 2>/dev/null
  git prune 2>/dev/null
  
  # Get repository size
  local repo_size=$(du -sh .git 2>/dev/null | cut -f1)
  
  print_success "Repository optimized (Git size: $repo_size)"
}

# Function to create repository backup without cleanup
create_repository_backup() {
  echo ""
  echo "=========================================="
  echo " Repository Backup Creation"
  echo "=========================================="
  echo ""

  read -p "Enter the path to the repository to back up: " repo_path
  if [[ -z "$repo_path" ]]; then
    print_error "Repository path cannot be empty"
    return 1
  fi

  repo_path=$(realpath "$repo_path" 2>/dev/null)
  if [[ ! -d "$repo_path" ]]; then
    print_error "Repository path does not exist: $repo_path"
    return 1
  fi

  if [[ ! -d "$repo_path/.git" ]]; then
    print_error "Not a git repository: $repo_path"
    return 1
  fi

  local repo_name=$(basename "$repo_path")
  local backup_dir="$HOME/backup"
  local timestamp
  timestamp=$(date +"%Y%m%d_%H%M%S")
  local backup_name="${repo_name}_backup_${timestamp}.tar.gz"

  mkdir -p "$backup_dir" || {
    print_error "Failed to create backup directory: $backup_dir"
    return 1
  }

  print_status "Creating backup archive: $backup_dir/$backup_name"
  (
    cd "$(dirname "$repo_path")" &&
    tar -czf "$backup_dir/$backup_name" "$(basename "$repo_path")"
  ) 2>/dev/null

  if [[ $? -ne 0 ]]; then
    print_error "Failed to create backup archive"
    return 1
  fi

  local backup_size
  backup_size=$(du -h "$backup_dir/$backup_name" | cut -f1)
  print_success "Backup created: $backup_name ($backup_size)"
  print_status "Location: $backup_dir/$backup_name"
}

# Function to restore repository from backup
restore_repository_backup() {
  echo ""
  echo "=========================================="
  echo " Repository Backup Restoration"
  echo "=========================================="
  echo ""
  
  local backup_dir="$HOME/backup"
  
  if [[ ! -d "$backup_dir" ]]; then
    print_error "Backup directory does not exist: $backup_dir"
    return 1
  fi
  
  # Find all backup files
  local backup_files=()
  while IFS= read -r -d '' file; do
    backup_files+=("$file")
  done < <(find "$backup_dir" -name "*_backup_*.tar.gz" -print0 2>/dev/null | sort -z)
  
  if [[ ${#backup_files[@]} -eq 0 ]]; then
    print_error "No backup files found in $backup_dir"
    return 1
  fi
  
  echo "Available backup files:"
  echo ""
  
  local i=1
  local backup_info=()
  for backup_file in "${backup_files[@]}"; do
    local filename=$(basename "$backup_file")
    local file_size=$(du -h "$backup_file" 2>/dev/null | cut -f1)
    local file_date=$(stat -c %y "$backup_file" 2>/dev/null | cut -d' ' -f1)
    echo "$i) $filename"
    echo "   Size: $file_size, Created: $file_date"
    echo "   Path: $backup_file"
    echo ""
    backup_info+=("$backup_file")
    i=$((i + 1))
  done
  
  read -p "Enter the number of the backup to restore (1-${#backup_files[@]}): " selection
  
  if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ $selection -lt 1 ]] || [[ $selection -gt ${#backup_files[@]} ]]; then
    print_error "Invalid selection"
    return 1
  fi
  
  local selected_backup="${backup_info[$((selection - 1))]}"
  local backup_filename=$(basename "$selected_backup")
  
  # Extract repository name from backup filename
  local repo_name=$(echo "$backup_filename" | sed 's/_backup_[0-9]*_[0-9]*\.tar\.gz$//')
  
  read -p "Enter the directory where you want to restore (press Enter for current directory): " restore_dir
  if [[ -z "$restore_dir" ]]; then
    restore_dir="."
  fi
  
  restore_dir=$(realpath "$restore_dir")
  
  if [[ ! -d "$restore_dir" ]]; then
    print_error "Restore directory does not exist: $restore_dir"
    return 1
  fi
  
  # Create timestamped directory name
  local timestamp=$(date +"%Y%m%d_%H%M%S")
  local restore_path="$restore_dir/${repo_name}_restored_${timestamp}"
  
  echo ""
  print_status "Selected backup: $backup_filename"
  print_status "Will restore to: $restore_path"
  echo ""
  
  read -p "Proceed with restoration? (y/N): " confirm_restore
  if [[ ! "$confirm_restore" =~ ^[Yy]$ ]]; then
    print_status "Restoration cancelled"
    return 0
  fi
  
  print_status "Extracting backup..."
  
  # Create temporary directory for extraction
  local temp_dir=$(mktemp -d)
  cd "$temp_dir"
  
  # Extract the backup
  tar -xzf "$selected_backup" 2>/dev/null
  if [[ $? -ne 0 ]]; then
    print_error "Failed to extract backup archive"
    rm -rf "$temp_dir"
    return 1
  fi
  
  # Find the extracted directory
  local extracted_dir=$(find . -maxdepth 1 -type d ! -name "." | head -1)
  if [[ -z "$extracted_dir" ]]; then
    print_error "Could not find extracted repository directory"
    rm -rf "$temp_dir"
    return 1
  fi
  
  # Move to final location
  mv "$extracted_dir" "$restore_path"
  if [[ $? -eq 0 ]]; then
    print_success "Repository restored successfully!"
    print_status "Restored to: $restore_path"
    
    # Show some info about the restored repository
    if [[ -d "$restore_path/.git" ]]; then
      cd "$restore_path"
      local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "unknown")
      local last_commit=$(git log -1 --format="%h %s" 2>/dev/null || echo "unknown")
      echo ""
      print_status "Repository info:"
      echo "  Commits: $commit_count"
      echo "  Last commit: $last_commit"
    fi
  else
    print_error "Failed to move restored repository to final location"
  fi
  
  # Cleanup
  rm -rf "$temp_dir"
}

# Function to clone a repository
clone_repository() {
  echo ""
  echo "=========================================="
  echo " Repository Clone Tool"
  echo "=========================================="
  echo ""
  
  # Get repository information
  read -p "Enter GitHub username/organization: " gh_user
  if [[ -z "$gh_user" ]]; then
    print_error "Username/organization cannot be empty"
    return 1
  fi
  
  read -p "Enter repository name: " repo_name
  if [[ -z "$repo_name" ]]; then
    print_error "Repository name cannot be empty"
    return 1
  fi
  
  read -p "Enter GitHub domain (press Enter for github.com): " github_url
  if [[ -z "$github_url" ]]; then
    github_url="github.com"
  else
    # Clean up domain input
    github_url=${github_url#https://}
    github_url=${github_url#http://}
    github_url=${github_url%/}
  fi
  
  read -p "Enter local directory name (press Enter for '$repo_name'): " local_dir
  if [[ -z "$local_dir" ]]; then
    local_dir="$repo_name"
  fi
  
  read -p "Enter target directory (press Enter for current directory): " target_dir
  if [[ -z "$target_dir" ]]; then
    target_dir="."
  fi
  
  # Convert to absolute path
  target_dir=$(realpath "$target_dir" 2>/dev/null || echo "$target_dir")
  local clone_path="$target_dir/$local_dir"
  
  # Check if target directory exists
  if [[ ! -d "$target_dir" ]]; then
    print_error "Target directory does not exist: $target_dir"
    return 1
  fi
  
  # Check if clone destination already exists
  if [[ -d "$clone_path" ]]; then
    print_error "Directory already exists: $clone_path"
    read -p "Do you want to remove it and continue? (y/N): " remove_existing
    if [[ "$remove_existing" =~ ^[Yy]$ ]]; then
      rm -rf "$clone_path"
      print_status "Removed existing directory: $clone_path"
    else
      print_status "Clone cancelled"
      return 0
    fi
  fi

  # Choose clone method
  echo ""
  print_status "Clone method options:"
  echo "1) HTTPS (public repositories, no authentication needed)"
  echo "2) HTTPS with authentication (private repositories)"
  echo "3) SSH (requires SSH key setup)"
  read -p "Choose clone method (1-3) [1]: " clone_method
  clone_method=${clone_method:-1}
  
  local repo_url
  case $clone_method in
    1)
      repo_url="https://$github_url/$gh_user/$repo_name.git"
      ;;
    2)
      print_status "GitHub Token Required (needs 'repo' scope)"
      read -s -p "Enter your GitHub Personal Access Token: " gh_token
      echo ""
      if [[ -z "$gh_token" ]]; then
        print_error "GitHub token cannot be empty"
        return 1
      fi
      repo_url="https://$gh_token@$github_url/$gh_user/$repo_name.git"
      ;;
    3)
      if [[ "$github_url" == "github.com" ]]; then
        repo_url="git@github.com:$gh_user/$repo_name.git"
      else
        repo_url="git@$github_url:$gh_user/$repo_name.git"
      fi
      ;;
    *)
      print_error "Invalid choice"
      return 1
      ;;
  esac
  
  # Choose branch (optional)
  read -p "Enter specific branch to clone (press Enter for default): " branch_name
  
  # Clone options
  echo ""
  print_status "Clone options:"
  echo "1) Full clone (complete history)"
  echo "2) Shallow clone (latest commit only)"
  echo "3) Shallow clone with specific depth"
  read -p "Choose clone option (1-3) [1]: " clone_option
  clone_option=${clone_option:-1}
  
  local clone_args=""
  case $clone_option in
    1)
      # Full clone - no additional args needed
      ;;
    2)
      clone_args="--depth 1"
      ;;
    3)
      read -p "Enter clone depth (number of commits): " clone_depth
      if [[ "$clone_depth" =~ ^[0-9]+$ ]] && [[ $clone_depth -gt 0 ]]; then
        clone_args="--depth $clone_depth"
      else
        print_error "Invalid depth. Using shallow clone (depth 1)"
        clone_args="--depth 1"
      fi
      ;;
    *)
      print_error "Invalid choice. Using full clone"
      ;;
  esac
  
  # Add branch specification if provided
  if [[ -n "$branch_name" ]]; then
    clone_args="$clone_args --branch $branch_name"
  fi
  
  # Show clone summary
  echo ""
  print_status "Clone Summary:"
  echo "  Repository: $gh_user/$repo_name"
  echo "  Source: $github_url"
  echo "  Method: $(case $clone_method in 1) HTTPS;; 2) HTTPS with auth;; 3) SSH;; esac)"
  echo "  Target: $clone_path"
  if [[ -n "$branch_name" ]]; then
    echo "  Branch: $branch_name"
  fi
  echo "  Options: $(case $clone_option in 1) Full clone;; 2) Shallow clone;; 3) Depth $clone_depth;; esac)"
  echo ""
  
  read -p "Proceed with clone? (y/N): " confirm_clone
  if [[ ! "$confirm_clone" =~ ^[Yy]$ ]]; then
    print_status "Clone cancelled"
    return 0
  fi
  
  # Perform the clone
  print_status "Cloning repository..."
  cd "$target_dir"
  
  local clone_cmd="git clone $clone_args \"$repo_url\""
  if [[ "$local_dir" != "$repo_name" ]]; then
    clone_cmd="$clone_cmd \"$local_dir\""
  fi
  
  print_status "Executing: git clone $clone_args [URL] $local_dir"
  
  if eval "$clone_cmd"; then
    print_success "Repository cloned successfully!"
    
    # Post-clone setup
    cd "$clone_path"
    
    # Show repository information
    echo ""
    print_status "Repository Information:"
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    local commit_count=$(git rev-list --count HEAD 2>/dev/null || echo "unknown")
    local last_commit=$(git log -1 --format="%h %s" 2>/dev/null || echo "unknown")
    local remote_url=$(git remote get-url origin 2>/dev/null || echo "unknown")
    
    echo "  Path: $clone_path"
    echo "  Current branch: $current_branch"
    echo "  Total commits: $commit_count"
    echo "  Last commit: $last_commit"
    echo "  Remote URL: $remote_url"
    
    # Show available branches
    echo ""
    print_status "Available branches:"
    git branch -a 2>/dev/null | head -10
    
    # Show repository size
    local repo_size=$(du -sh . 2>/dev/null | cut -f1)
    echo ""
    print_status "Repository size: $repo_size"
    
    # Optional: Configure git user if not set
    if ! git config user.name >/dev/null 2>&1 || ! git config user.email >/dev/null 2>&1; then
      echo ""
      print_warning "Git user configuration not found"
      read -p "Do you want to configure git user for this repository? (y/N): " config_user
      if [[ "$config_user" =~ ^[Yy]$ ]]; then
        configure_git_user_local
      fi
    fi
    
    # Optional: Setup additional remotes
    echo ""
    read -p "Do you want to add additional remotes? (y/N): " add_remotes
    if [[ "$add_remotes" =~ ^[Yy]$ ]]; then
      setup_additional_remotes
    fi
    
    echo ""
    print_success "Clone operation completed!"
    print_status "You can now work with the repository at: $clone_path"
    
  else
    print_error "Failed to clone repository"
    print_status "Possible causes:"
    echo "  - Repository does not exist or is private"
    echo "  - Invalid authentication credentials"
    echo "  - Network connectivity issues"
    echo "  - SSH key not configured (for SSH method)"
    echo "  - Insufficient permissions"
    return 1
  fi
}

# Function to configure git user locally
configure_git_user_local() {
  read -p "Enter your name: " git_user_name
  read -p "Enter your email: " git_user_email
  
  if [[ -n "$git_user_name" ]] && [[ -n "$git_user_email" ]]; then
    git config user.name "$git_user_name"
    git config user.email "$git_user_email"
    print_success "Git user configured locally"
  else
    print_warning "Git user configuration skipped"
  fi
}

# Function to setup additional remotes
setup_additional_remotes() {
  while true; do
    read -p "Enter remote name (or 'done' to finish): " remote_name
    if [[ "$remote_name" == "done" ]]; then
      break
    fi
    
    if [[ -z "$remote_name" ]]; then
      print_error "Remote name cannot be empty"
      continue
    fi
    
    # Check if remote already exists
    if git remote get-url "$remote_name" >/dev/null 2>&1; then
      print_warning "Remote '$remote_name' already exists"
      continue
    fi
    
    read -p "Enter remote URL: " remote_url
    if [[ -z "$remote_url" ]]; then
      print_error "Remote URL cannot be empty"
      continue
    fi
    
    if git remote add "$remote_name" "$remote_url"; then
      print_success "Added remote: $remote_name -> $remote_url"
    else
      print_error "Failed to add remote: $remote_name"
    fi
  done
}

# Function to clone all repositories for a GitHub user
clone_all_user_repositories() {
  echo ""
  echo "=========================================="
  echo " Bulk Clone - All User Repositories"
  echo "=========================================="
  echo ""
  
  # Get GitHub user information
  read -p "Enter GitHub username to clone all repositories from: " gh_user
  if [[ -z "$gh_user" ]]; then
    print_error "Username cannot be empty"
    return 1
  fi
  
  read -p "Enter GitHub domain (press Enter for github.com): " github_url
  if [[ -z "$github_url" ]]; then
    github_url="github.com"
    api_url="https://api.github.com"
  else
    # Clean up domain input
    github_url=${github_url#https://}
    github_url=${github_url#http://}
    github_url=${github_url%/}
    
    if [[ "$github_url" == "github.com" ]]; then
      api_url="https://api.github.com"
    else
      api_url="https://$github_url/api/v3"
    fi
  fi
  
  read -p "Enter target directory (press Enter for ~/Downloads/GIT): " target_dir
  if [[ -z "$target_dir" ]]; then
    target_dir="$HOME/Downloads/GIT"
  fi
  
  # Convert to absolute path
  target_dir=$(realpath "$target_dir" 2>/dev/null || echo "$target_dir")
  
  # Create target directory if it doesn't exist
  if [[ ! -d "$target_dir" ]]; then
    read -p "Target directory doesn't exist. Create it? (y/N): " create_dir
    if [[ "$create_dir" =~ ^[Yy]$ ]]; then
      mkdir -p "$target_dir"
      if [[ $? -ne 0 ]]; then
        print_error "Failed to create target directory: $target_dir"
        return 1
      fi
      print_success "Created target directory: $target_dir"
    else
      print_error "Target directory does not exist: $target_dir"
      return 1
    fi
  fi
  
  # Check if we need authentication
  echo ""
  echo "Repository access options:"
  echo "1) Public repositories only (no authentication)"
  echo "2) All repositories including private (requires authentication)"
  read -p "Choose option (1-2) [1]: " access_choice
  access_choice=${access_choice:-1}
  
  local auth_header=""
  local api_endpoint
  
  case $access_choice in
    1)
      api_endpoint="$api_url/users/$gh_user/repos"
      ;;
    2)
      print_status "GitHub Token Required (needs 'repo' scope)"
      read -s -p "Enter your GitHub Personal Access Token: " gh_token
      echo ""
      if [[ -z "$gh_token" ]]; then
        print_error "GitHub token cannot be empty for private repositories"
        return 1
      fi
      auth_header="Authorization: token $gh_token"
      api_endpoint="$api_url/user/repos"
      ;;
    *)
      print_error "Invalid choice"
      return 1
      ;;
  esac
  
  # Choose clone method
  echo ""
  print_status "Clone method options:"
  echo "1) HTTPS (recommended for most users)"
  echo "2) SSH (requires SSH key setup)"
  read -p "Choose clone method (1-2) [1]: " clone_method
  clone_method=${clone_method:-1}
  
  # Repository filtering options
  echo ""
  print_status "Repository filtering options:"
  echo "1) Clone all repositories"
  echo "2) Skip forks"
  echo "3) Only forks"
  echo "4) Only public repositories"
  echo "5) Only private repositories"
  read -p "Choose filtering option (1-5) [1]: " filter_option
  filter_option=${filter_option:-1}
  
  # Clone options
  echo ""
  print_status "Clone depth options:"
  echo "1) Full clone (complete history)"
  echo "2) Shallow clone (latest commit only)"
  read -p "Choose clone option (1-2) [1]: " depth_option
  depth_option=${depth_option:-1}
  
  local clone_args=""
  if [[ "$depth_option" == "2" ]]; then
    clone_args="--depth 1"
  fi
  
  # Fetch repository list
  print_status "Fetching repository list for user: $gh_user..."
  
  local temp_file="/tmp/github_repos_$$.json"
  local page=1
  local all_repos=()
  
  # Handle pagination
  while true; do
    local page_endpoint="$api_endpoint?page=$page&per_page=100"
    
    local curl_cmd="curl -s"
    if [[ -n "$auth_header" ]]; then
      curl_cmd="$curl_cmd -H \"$auth_header\""
    fi
    curl_cmd="$curl_cmd \"$page_endpoint\""
    
    eval "$curl_cmd" > "$temp_file"
    
    # Check if we got an error
    if [[ $? -ne 0 ]]; then
      print_error "Failed to fetch repository list"
      rm -f "$temp_file"
      return 1
    fi
    
    # Check for API errors
    local error_message=$(grep -o '"message":"[^"]*"' "$temp_file" 2>/dev/null | cut -d'"' -f4)
    if [[ -n "$error_message" ]]; then
      print_error "GitHub API error: $error_message"
      rm -f "$temp_file"
      return 1
    fi
    
    # Check if page is empty (end of pagination)
    local page_count=$(jq length "$temp_file" 2>/dev/null || echo "0")
    if [[ "$page_count" == "0" ]]; then
      break
    fi
    
    # Add repositories to our list
    if command -v jq >/dev/null 2>&1; then
      while IFS= read -r repo; do
        all_repos+=("$repo")
      done < <(jq -r '.[] | @base64' "$temp_file")
    else
      print_warning "jq not installed. Using basic parsing..."
      while IFS= read -r line; do
        if [[ "$line" =~ \"clone_url\":\ *\"([^\"]+)\" ]]; then
          all_repos+=("${BASH_REMATCH[1]}")
        fi
      done < "$temp_file"
    fi
    
    page=$((page + 1))
  done
  
  rm -f "$temp_file"
  
  if [[ ${#all_repos[@]} -eq 0 ]]; then
    print_error "No repositories found for user: $gh_user"
    return 1
  fi
  
  print_success "Found ${#all_repos[@]} repositories"
  
  # Filter repositories based on user choice
  local filtered_repos=()
  local repo_count=0
  
  for repo_data in "${all_repos[@]}"; do
    if command -v jq >/dev/null 2>&1; then
      local repo_info=$(echo "$repo_data" | base64 -d)
      local clone_url=$(echo "$repo_info" | jq -r '.clone_url')
      local ssh_url=$(echo "$repo_info" | jq -r '.ssh_url')
      local is_fork=$(echo "$repo_info" | jq -r '.fork')
      local is_private=$(echo "$repo_info" | jq -r '.private')
      local repo_name=$(echo "$repo_info" | jq -r '.name')
    else
      # Basic parsing without jq
      local clone_url="$repo_data"
      local ssh_url="$repo_data"
      local is_fork="false"
      local is_private="false"
      local repo_name=$(basename "$clone_url" .git)
    fi
    
    # Apply filtering
    local include_repo=true
    case $filter_option in
      2) # Skip forks
        if [[ "$is_fork" == "true" ]]; then
          include_repo=false
        fi
        ;;
      3) # Only forks
        if [[ "$is_fork" != "true" ]]; then
          include_repo=false
        fi
        ;;
      4) # Only public
        if [[ "$is_private" == "true" ]]; then
          include_repo=false
        fi
        ;;
      5) # Only private
        if [[ "$is_private" != "true" ]]; then
          include_repo=false
        fi
        ;;
    esac
    
    if [[ "$include_repo" == "true" ]]; then
      if [[ "$clone_method" == "2" ]]; then
        filtered_repos+=("$ssh_url|$repo_name")
      else
        filtered_repos+=("$clone_url|$repo_name")
      fi
      repo_count=$((repo_count + 1))
    fi
  done
  
  if [[ ${#filtered_repos[@]} -eq 0 ]]; then
    print_error "No repositories match the selected filter criteria"
    return 1
  fi
  
  echo ""
  print_status "Repositories to clone (after filtering): $repo_count"
  echo ""
  print_status "Clone Summary:"
  echo "  User: $gh_user"
  echo "  Target: $target_dir/$gh_user"
  echo "  Method: $(case $clone_method in 1) HTTPS;; 2) SSH;; esac)"
  echo "  Filter: $(case $filter_option in 1) All repositories;; 2) Skip forks;; 3) Only forks;; 4) Only public;; 5) Only private;; esac)"
  echo "  Depth: $(case $depth_option in 1) Full clone;; 2) Shallow clone;; esac)"
  echo "  Count: $repo_count repositories"
  echo ""
  
  read -p "Proceed with bulk clone? (y/N): " confirm_clone
  if [[ ! "$confirm_clone" =~ ^[Yy]$ ]]; then
    print_status "Bulk clone cancelled"
    return 0
  fi
  
  # Create user directory within target directory
  local user_dir="$target_dir/$gh_user"
  
  print_status "Creating user directory: $user_dir"
  if [[ ! -d "$user_dir" ]]; then
    mkdir -p "$user_dir"
    if [[ $? -ne 0 ]]; then
      print_error "Failed to create user directory: $user_dir"
      return 1
    fi
    print_success "Created user directory: $user_dir"
  else
    print_status "User directory already exists: $user_dir"
  fi
  
  # Perform bulk cloning
  print_status "Starting bulk clone operation..."
  echo ""
  
  local success_count=0
  local error_count=0
  local skipped_count=0
  
  cd "$user_dir"
  
  for repo_entry in "${filtered_repos[@]}"; do
    local repo_url="${repo_entry%|*}"
    local repo_name="${repo_entry#*|}"
    local local_path="$user_dir/$repo_name"
    
    echo "----------------------------------------"
    print_status "Cloning: $repo_name"
    
    # Check if repository already exists
    if [[ -d "$local_path" ]]; then
      print_warning "Directory already exists: $repo_name"
      read -p "  Skip (s), Overwrite (o), or Abort (a)? [s]: " action
      action=${action:-s}
      
      case $action in
        s|S)
          print_status "Skipped: $repo_name"
          skipped_count=$((skipped_count + 1))
          continue
          ;;
        o|O)
          rm -rf "$local_path"
          print_status "Removed existing directory: $repo_name"
          ;;
        a|A)
          print_status "Bulk clone aborted by user"
          break
          ;;
        *)
          print_status "Skipped: $repo_name"
          skipped_count=$((skipped_count + 1))
          continue
          ;;
      esac
    fi
    
    # Perform the clone
    if git clone $clone_args "$repo_url" "$repo_name" >/dev/null 2>&1; then
      print_success "Cloned: $repo_name"
      success_count=$((success_count + 1))
    else
      print_error "Failed: $repo_name"
      error_count=$((error_count + 1))
    fi
  done
  
  # Summary report
  echo ""
  echo "=========================================="
  print_success "Bulk Clone Operation Complete"
  echo "=========================================="
  echo ""
  print_status "Summary:"
  echo "  Total repositories: $repo_count"
  echo "  Successfully cloned: $success_count"
  echo "  Failed: $error_count"
  echo "  Skipped: $skipped_count"
  echo "  Target directory: $user_dir"
  echo ""
  
  if [[ $success_count -gt 0 ]]; then
    print_success "Successfully cloned $success_count repositories"
  fi
  
  if [[ $error_count -gt 0 ]]; then
    print_warning "$error_count repositories failed to clone"
    echo "  Common causes: network issues, authentication problems, or repository access restrictions"
  fi
  
  if [[ $skipped_count -gt 0 ]]; then
    print_status "$skipped_count repositories were skipped (already existed)"
  fi
}

# Function to check GitHub API rate limits
check_api_rate_limits() {
  local api_url="$1"
  local gh_token="$2"
  
  print_status "Checking GitHub API rate limits..."
  
  local rate_limit_response=$(curl -s \
    -H "Authorization: token $gh_token" \
    -H "Accept: application/vnd.github.v3+json" \
    "$api_url/rate_limit")
  
  local remaining=$(echo "$rate_limit_response" | grep -o '"remaining":[0-9]*' | head -1 | cut -d':' -f2)
  local reset_time=$(echo "$rate_limit_response" | grep -o '"reset":[0-9]*' | head -1 | cut -d':' -f2)
  local reset_date=$(date -d @"$reset_time" 2>/dev/null || date -r "$reset_time" 2>/dev/null)
  
  if [[ -z "$remaining" ]]; then
    print_warning "Could not retrieve rate limit information"
    return 0
  fi
  
  print_status "API calls remaining: $remaining"
  print_status "Rate limit resets at: $reset_date"
  
  if [[ $remaining -lt 10 ]]; then
    print_warning "GitHub API rate limit is almost reached!"
    print_warning "Only $remaining requests remaining until $reset_date"
    read -p "Continue anyway? (y/N): " continue_low_rate
    if [[ ! "$continue_low_rate" =~ ^[Yy]$ ]]; then
      print_status "Operation cancelled to avoid rate limiting"
      return 1
    fi
  fi
  
  return 0
}

# Add this to handle GitHub tokens more securely
secure_get_token() {
  local token_env_var="GITHUB_TOKEN"
  
  # Try to get token from environment
  if [[ -n "${!token_env_var}" ]]; then
    echo "${!token_env_var}"
    return 0
  fi
  
  # Try to get token from git credential helper
  if command -v git >/dev/null 2>&1; then
    local saved_token=$(git config --get github.token 2>/dev/null)
    if [[ -n "$saved_token" ]]; then
      echo "$saved_token"
      return 0
    fi
  fi
  
  # Prompt for token
  local token=""
  read -s -p "Enter your GitHub Personal Access Token: " token
  echo ""
  
  if [[ -z "$token" ]]; then
    return 1
  fi
  
  # Ask if user wants to save token
  read -p "Save token for future use? (y/N): " save_token
  if [[ "$save_token" =~ ^[Yy]$ ]]; then
    read -p "Save in: [1] git config, [2] .env file, [3] don't save [3]: " save_option
    save_option=${save_option:-3}
    
    case $save_option in
      1)
        git config --global github.token "$token" 2>/dev/null && \
          print_success "Token saved in git config" || \
          print_error "Failed to save token in git config"
        ;;
      2)
        echo "export GITHUB_TOKEN=$token" >> ~/.env && \
          print_success "Token saved in ~/.env file. Add 'source ~/.env' to your shell profile." || \
          print_error "Failed to save token in ~/.env file"
        chmod 600 ~/.env 2>/dev/null || true
        ;;
    esac
  fi
  
  echo "$token"
  return 0
}

# Parse command line arguments
case "${1:-}" in
  -h|--help)
    show_help
    exit 0
    ;;
  -c|--create)
    echo "=========================================="
    echo " GitHub Project Creation"
    echo "=========================================="
    create_repository
    exit 0
    ;;
  -d|--delete)
    remove_repository
    exit 0
    ;;
  -l|--clone)
    clone_repository
    exit 0
    ;;
  -b|--bulk-clone)
    clone_all_user_repositories
    exit 0
    ;;
  -f|--fix)
    fix_git_issues
    exit 0
    ;;
  -a|--auto-commit)
    auto_commit_repositories
    exit 0
    ;;
  -p|--protect)
    protect_repository
    exit 0
    ;;
  -m|--manage-pr)
    manage_pull_requests
    exit 0
    ;;
  -g|--ga-cleanup)
    cleanup_repository_for_ga
    exit 0
    ;;
  -r|--restore)
    restore_repository_backup
    exit 0
    ;;
  "")
    # No arguments, continue with interactive menu
    ;;
  *)
    print_error "Unknown option: $1"
    echo "Use --help for usage information"
    exit 1
    ;;
esac

# Interactive menu
echo ""
echo "=========================================="
echo " GitHub Repository Manager v4.2.3"
echo "=========================================="
echo ""
echo "Choose an action:"
echo "1) Repository Operations"
echo "2) Bulk Operations"
echo "3) Status & Reports"
echo "4) Maintenance & Cleanup"
echo "5) Exit"
echo ""
read -p "Enter your choice (1-5): " main_choice

case $main_choice in
  1)
    echo ""
    echo "Repository Operations:"
    echo "  1) Create new repository"
    echo "  2) Clone existing repository"
    echo "  3) Delete repository (GitHub + Local)"
    echo "  4) Backup/Restore from backup"
    echo "  5) Fix git repository issues"
    echo "  6) Manage pull requests (list, merge, close)"
    echo "  7) Manage repository secrets"
    echo "  8) Set up branch protection"
    echo "  9) Back"
    read -p "Enter your choice (1-9): " repo_choice
    case $repo_choice in
      1) create_repository ;;
      2) clone_repository ;;
      3) remove_repository ;;
      4)
        echo ""
        echo "Backup/Restore from backup:"
        echo "  1) Backup repository now"
        echo "  2) Restore repository from backup"
        echo "  3) Back"
        read -p "Enter your choice (1-3): " backup_restore_choice
        case $backup_restore_choice in
          1) create_repository_backup ;;
          2) restore_repository_backup ;;
          3) ;;
          *) print_error "Invalid choice." ;;
        esac
        ;;
      5) fix_git_issues ;;
      6) manage_pull_requests ;;
      7) manage_repository_secrets ;;
      8) protect_repository ;;
      9) ;;
      *) print_error "Invalid choice." ;;
    esac
    ;;
  2)
    echo ""
    echo "Bulk Operations:"
    echo "  1) Auto-commit & push multiple repositories"
    echo "  2) Bulk clone all user repositories"
    echo "  3) Scan folders for git repositories"
    echo "  4) Scan for local git repos needing push"
    echo "  5) Back"
    read -p "Enter your choice (1-5): " bulk_choice
    case $bulk_choice in
      1) auto_commit_repositories ;;
      2) clone_all_user_repositories ;;
      3) check_folders_for_git_repos ;;
      4) scan_and_push_git_repos ;;
      5) ;;
      *) print_error "Invalid choice." ;;
    esac
    ;;
  3)
    echo ""
    echo "Status & Reports:"
    echo "  1) Generate quick repository status report"
    echo "  2) Check GitHub API rate limits"
    echo "  3) Back"
    read -p "Enter your choice (1-3): " status_choice
    case $status_choice in
      1) generate_repository_report ;;
      2)
        read -p "Enter GitHub API URL (press Enter for api.github.com): " api_url
        api_url=${api_url:-"https://api.github.com"}
        gh_token=$(secure_get_token)
        if [[ -n "$gh_token" ]]; then
          check_api_rate_limits "$api_url" "$gh_token"
        else
          print_error "GitHub token required to check rate limits"
        fi
        ;;
      3) ;;
      *) print_error "Invalid choice." ;;
    esac
    ;;
  4)
    echo ""
    echo "Maintenance & Cleanup:"
    echo "  1) Cleanup repository for GA release (with backup)"
    echo "  2) Back"
    read -p "Enter your choice (1-2): " maint_choice
    case $maint_choice in
      1) cleanup_repository_for_ga ;;
      2) ;;
      *) print_error "Invalid choice." ;;
    esac
    ;;
  5)
    print_status "Goodbye!"
    exit 0
    ;;
  *)
    print_error "Invalid choice. Please run the script again."
    exit 1
    ;;
esac

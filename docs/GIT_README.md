# Git workflow for qld_public_dental_list

# After meaningful changes
git status
git checkout main

# what kind of change? name the branch
    git checkout -b feature/load_data
    eg. feature/fix/experiment

# Stage + commit
git add . |all| 
    git add sql/ |folder| 
    git add sql/load_data.sql |file|
    
git commit -m "Describe changes"

# Pull remote changes before pushing
git pull origin main --rebase

# Push local commits
git push -u origin main
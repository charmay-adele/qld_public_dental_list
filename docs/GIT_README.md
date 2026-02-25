# Git workflow for qld_public_dental_list

# After meaningful changes
git status

# Stage + commit
git add .
git commit -m "Describe changes"

# Pull remote changes before pushing
git pull origin main --rebase

# Push local commits
git push -u origin main
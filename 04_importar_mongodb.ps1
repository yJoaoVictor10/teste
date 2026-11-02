
# Importação do dataset Oracle para MongoDB
# Database: sprint4
# Collection: animais

mongoimport `
    --uri "mongodb://localhost:27017" `
    --db sprint4 `
    --collection animais `
    --file "./03_animais.json" `
    --jsonArray `
    --drop

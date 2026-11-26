#!/usr/bin/env bash
# Restaura um dump no MySQL do container o mais rápido possível.
#
#   scripts/mysql-restore.sh <banco> <arquivo.sql | .sql.gz | .sql.zst>
#
# Cria o banco se ele não existir e desliga, só nesta sessão, as checagens de
# chave estrangeira e de unicidade e o autocommit, que são o que mais atrasa um
# import. Se o pv estiver instalado, mostra o progresso.
set -euo pipefail

CONTAINER="${MYSQL_CONTAINER:-dabase-mysql}"
PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"

if [ $# -ne 2 ]; then
    echo "uso: $0 <banco> <arquivo.sql|.sql.gz|.sql.zst>" >&2
    exit 1
fi
DB="$1"
FILE="$2"
[ -f "$FILE" ] || { echo "arquivo não encontrado: $FILE" >&2; exit 1; }

case "$FILE" in
    *.gz)  DECOMPRESS=(gzip -dc) ;;
    *.zst) DECOMPRESS=(zstd -dc) ;;
    *)     DECOMPRESS=(cat) ;;
esac

if command -v pv >/dev/null; then
    READ=(pv "$FILE")
else
    READ=(cat "$FILE")
fi

docker exec -e MYSQL_PWD="$PASSWORD" "$CONTAINER" \
    mysql -uroot -e "CREATE DATABASE IF NOT EXISTS \`$DB\`"

{
    echo "SET foreign_key_checks=0; SET unique_checks=0; SET autocommit=0;"
    "${READ[@]}" | "${DECOMPRESS[@]}"
    echo ";COMMIT; SET unique_checks=1; SET foreign_key_checks=1;"
} | docker exec -i -e MYSQL_PWD="$PASSWORD" "$CONTAINER" \
    mysql -uroot --max-allowed-packet=1G "$DB"

echo "restore de $FILE em $DB concluído"

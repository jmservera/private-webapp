#!/bin/sh

generate_sid() {
    # Remove hyphens and extract parts in correct order
    guid_clean=$(echo "$1" | tr -d '-')
    
    # Extract and reorder parts directly
    p1=$(expr substr "$guid_clean" 7 2)$(expr substr "$guid_clean" 5 2)$(expr substr "$guid_clean" 3 2)$(expr substr "$guid_clean" 1 2)
    p2=$(expr substr "$guid_clean" 11 2)$(expr substr "$guid_clean" 9 2)
    p3=$(expr substr "$guid_clean" 15 2)$(expr substr "$guid_clean" 13 2)
    p4=$(expr substr "$guid_clean" 17 16)
    
    # Combine, convert to uppercase and add prefix
    echo "0x$(echo "${p1}${p2}${p3}${p4}" | tr '[:lower:]' '[:upper:]')"
}

#create user [${APPIDENTITYNAME}] FROM EXTERNAL PROVIDER

# https://stackoverflow.com/questions/76995900/how-to-grant-a-managed-identity-permissions-to-an-azure-sql-database-using-iac
# appIdentityName$appId = 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx' (this is the clientid)
# $sid = "0x" + [System.BitConverter]::ToString(([guid]$appId).ToByteArray()).Replace("-", "")

SID=$(generate_sid "${APPIDENTITYID}")

wget https://github.com/microsoft/go-sqlcmd/releases/download/v1.8.0/sqlcmd-linux-amd64.tar.bz2
tar x -f sqlcmd-linux-amd64.tar.bz2 -C .

# before running this the MI needs to have Directory Readers role in Entra

cat <<SCRIPT_END > ./initDb.sql
drop user if exists [${APPIDENTITYNAME}]
go
CREATE USER [${APPIDENTITYNAME}] WITH DEFAULT_SCHEMA=[dbo], SID = $SID, TYPE = E;
go
-- alter role db_owner add member [${APPIDENTITYNAME}]
-- go
IF object_id('${TABLENAME}', 'U') is not null
    create table ${TABLENAME} ([key] nvarchar(50) PRIMARY KEY, [stored_value] nvarchar(255));
go
SCRIPT_END

echo "Initializing database ${DBNAME} on server ${DBSERVER}"
./sqlcmd -S "${DBSERVER}" -d "${DBNAME}" --authentication-method ActiveDirectoryManagedIdentity -U "${CLIENTID}" -i ./initDb.sql
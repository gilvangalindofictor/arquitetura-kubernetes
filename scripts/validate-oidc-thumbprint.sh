#!/bin/bash
# scripts/validate-oidc-thumbprint.sh

OIDC_ARN="arn:aws:iam::891377105802:oidc-provider/oidc.eks.us-east-1.amazonaws.com/id/EC913B145BF356481CBE823532F09150"

CURRENT=$(aws iam get-open-id-connect-provider --open-id-connect-provider-arn $OIDC_ARN --query 'ThumbprintList[0]' --output text)
EXPECTED=$(echo | openssl s_client -servername oidc.eks.us-east-1.amazonaws.com -connect oidc.eks.us-east-1.amazonaws.com:443 2>/dev/null | openssl x509 -fingerprint -noout -sha1 | sed 's/://g' | sed 's/.*=//' | tr '[:upper:]' '[:lower:]')

if [ "$CURRENT" != "$EXPECTED" ]; then
  echo "⚠️ OIDC thumbprint desatualizado!"
  echo "Atual: $CURRENT"
  echo "Esperado: $EXPECTED"
  exit 1
fi

echo "✅ OIDC thumbprint OK"

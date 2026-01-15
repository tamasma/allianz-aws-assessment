# Scenario 1: Encryption Management - KMS Key Rotation

## Architecture Context

As shown in the diagram, we have a centralized KMS architecture where:
- KMS keys are managed in a dedicated Security Account
- Keys are organized by environment (Dev/Prod) and service type
- We use external key material (BYOK) imported from on-premise HSM
- Keys are shared cross-account with Dev and Prod accounts
- Aliases are used to reference keys

---

## Question 1: What are the main challenges to apply key rotation? And what impacts you can identify?

### Main Challenges

1. **No automatic rotation for BYOK**: AWS automatic key rotation doesn't work with imported key material. Each rotation must be done manually.

2. **Cross-account coordination**: Keys live in the Security Account but are used by Dev and Prod accounts. Any rotation needs careful synchronization.

3. **HSM synchronization**: New key material must be generated in the on-premise HSM, properly exported, and imported to KMS.

4. **Service downtime risk**: A poorly planned rotation can temporarily break access to encrypted data.

### Impacts by Service

| Service | Impact |
|---------|--------|
| **S3** | Minimal - existing objects remain readable with old key version, new objects use new version |
| **RDS** | High - requires snapshot, restore with new key, and endpoint switch. Needs maintenance window |
| **DynamoDB** | Medium - re-encryption may impact performance during the process |

---

## Question 2: From your perspective, what are the steps of applying key rotation (high level description)?

1. **Generate new key material in on-premise HSM**

2. **Request import token from AWS KMS** - AWS provides a temporary public key for wrapping

3. **Wrap the key material** - Use AWS public key to encrypt the new key material in the HSM

4. **Import wrapped material to KMS** - Creates new key version

5. **Update aliases if needed** - Point to the new key

6. **Verify encryption/decryption works** - Test before finalizing

7. **Monitor for errors** - Check CloudTrail for decryption failures

8. **Document the rotation** - Record in change management system

---

## Question 3: After applying the rotation on keys, we're required to have monitoring on resources to identify - at any given time - resources (RDS, DynamoDB, S3) that are not compliant (resources where rotation is not applied). How could we achieve this requirement with an AWS managed service?

### Solution: AWS Config with Custom Rules

For BYOK, we need a custom AWS Config rule since the standard `cmk-backing-key-rotation-enabled` rule only checks for automatic rotation (which doesn't apply to imported keys).

**Approach**: Use a tag `LastRotationDate` on KMS keys, and a Lambda function to verify if rotation was done within the required period:

```python
import boto3
from datetime import datetime

def evaluate_compliance(configuration_item, rule_parameters):
    kms = boto3.client('kms')

    key_id = configuration_item.get('configuration', {}).get('kmsKeyId')
    if not key_id:
        return 'NOT_APPLICABLE'

    try:
        tags = kms.list_resource_tags(KeyId=key_id)

        for tag in tags.get('Tags', []):
            if tag['TagKey'] == 'LastRotationDate':
                last_rotation = datetime.fromisoformat(tag['TagValue'])
                days_since_rotation = (datetime.now() - last_rotation).days
                if days_since_rotation > 365:
                    return 'NON_COMPLIANT'
                return 'COMPLIANT'

        return 'NON_COMPLIANT'  # No rotation date found

    except Exception:
        return 'NON_COMPLIANT'
```

This rule will flag any RDS, DynamoDB, or S3 resource using a KMS key that hasn't been rotated in over a year.

---

## Question 4: What's the best way to secure key material during their transportation from HSM to AWS KMS?

### Secure Transport Process

1. **Get import parameters from AWS KMS**:
```bash
aws kms get-parameters-for-import \
    --key-id <key-id> \
    --wrapping-algorithm RSAES_OAEP_SHA_256 \
    --wrapping-key-spec RSA_2048
```

2. **Wrap key material in HSM** using AWS's public key - the key material is never exposed in plaintext outside the HSM

3. **Import wrapped material**:
```bash
aws kms import-key-material \
    --key-id <key-id> \
    --encrypted-key-material fileb://encrypted-key.bin \
    --import-token fileb://import-token.bin \
    --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE
```

### Best Practices

- Use **RSAES_OAEP_SHA_256** wrapping algorithm (most secure)
- Transport over **AWS Direct Connect** or encrypted VPN
- Import token is **single-use** and expires in 24 hours
- Verify key material integrity with hash before and after transport

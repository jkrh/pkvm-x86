#!/usr/bin/env python3

"""
Generates a correctly structured EFI_VARIABLE_AUTHENTICATION_2 payload
for use with EDK2-based firmware.
"""

import struct
from datetime import datetime
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.serialization import pkcs7
from cryptography.hazmat.backends import default_backend
import uuid

def create_auth_payload(
    key_file, cert_file, data_file, output_file, timestamp_str,
    variable_name, vendor_guid, attributes
):
    """
    Reads all input files, generates the authenticated payload,
    and writes it to the output file.
    """

    print(f"Loading variable data from '{data_file}'...")
    with open(data_file, 'rb') as f:
        variable_payload = f.read()

    print(f"Loading private key from '{key_file}'...")
    with open(key_file, 'rb') as f:
        private_key = serialization.load_pem_private_key(
            f.read(), password=None, backend=default_backend()
        )

    print(f"Loading certificate from '{cert_file}'...")
    with open(cert_file, 'rb') as f:
        cert = x509.load_pem_x509_certificate(f.read(), default_backend())

    try:
        ts = datetime.strptime(timestamp_str, '%Y-%m-%d %H:%M:%S')
    except ValueError:
        print(f"Error: Invalid timestamp format. Use 'YYYY-MM-DD HH:MM:SS'")
        return

    efi_time = struct.pack(
        '<H6BIhBB',  # H=Year, 6B=M,D,H,M,S,Pad1, I=Nano, h=TZ, B=Daylight, B=Pad2
        ts.year, ts.month, ts.day, ts.hour, ts.minute, ts.second,
        0, 0, 0, 0, 0
    )

    print(f"Signing for: Variable='{variable_name}', GUID='{vendor_guid}'")

    var_name_bytes = variable_name.encode('utf-16le')
    vendor_guid_bytes = uuid.UUID(vendor_guid).bytes_le
    attributes_bytes = struct.pack('<L', attributes)

    data_to_sign = (
        var_name_bytes +
        vendor_guid_bytes +
        attributes_bytes +
        efi_time +
        variable_payload
    )
    print(f"Total size of data to be signed: {len(data_to_sign)} bytes")

    # Create PKCS#7 detached signature
    print("Generating PKCS#7 signature with SHA-256...")
    options = [pkcs7.PKCS7Options.DetachedSignature]

    builder = pkcs7.PKCS7SignatureBuilder()
    builder = builder.set_data(data_to_sign)

    print("Embedding signer certificate into PKCS#7 blob...")
    builder = builder.add_certificate(cert)
    builder = builder.add_signer(
        cert, private_key, hashes.SHA256()
    )

    pkcs7_blob = builder.sign(
        encoding=serialization.Encoding.DER,
        options=options
    )

    pkcs7_size = len(pkcs7_blob)
    print(f"PKCS#7 signature size: {pkcs7_size} bytes")

    efi_cert_pkcs7_guid = bytes.fromhex('9DD2AF4ADF68EE498AA9347D375665A7')

    win_cert_hdr_size = 8 + 16 + pkcs7_size  # Header (8) + GUID (16) + Pkcs7

    win_cert_header = struct.pack(
        '<LHH',
        win_cert_hdr_size,
        0x0200,            # wRevision
        0x0EF1             # wCertificateType (WIN_CERT_TYPE_EFI_GUID)
    )

    auth_header = efi_time + win_cert_header + efi_cert_pkcs7_guid + pkcs7_blob
    total_payload = auth_header + variable_payload

    print(f"Total payload size: {len(total_payload)} bytes")
    print(f"Writing to '{output_file}'...")
    with open(output_file, 'wb') as f:
        f.write(total_payload)

    print("Done.")

if __name__ == "__main__":
    # --- Configuration Variables ---
    PRIV_KEY_FILE = 'MOK-PK.priv'
    CERT_FILE = 'MOK-PK.pem'
    TIMESTAMP_STR = '2030-01-01 00:00:00'
    DATA_FILE = 'empty_file.bin'
    OUTPUT_FILE = 'DeletePK.auth'

    VARIABLE_NAME = 'PK'
    VENDOR_GUID = '8be4df61-93ca-11d2-aa0d-00e098032b8c'
    ATTRIBUTES = 0x27 # NV + BS + RT + TIME_BASED_AUTH
    # -----------------------------

    create_auth_payload(
        PRIV_KEY_FILE,
        CERT_FILE,
        DATA_FILE,
        OUTPUT_FILE,
        TIMESTAMP_STR,
        VARIABLE_NAME,
        VENDOR_GUID,
        ATTRIBUTES
    )

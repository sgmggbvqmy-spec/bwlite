// The kinds of item (login, card, identity, ...) and the fields each kind has.

import Foundation

/// One field of a card, identity, SSH key, bank account, driver's license or passport.
nonisolated struct FieldSpec {
    let key: String        // the name the server uses
    let label: String
    var secret = false     // shown as dots until the pointer is over it
    var multiline = false
    var placeholder = ""
}

/// The kinds of item a Bitwarden vault holds. The raw value is the number the server uses.
nonisolated enum ItemKind: Int, CaseIterable {
    case login = 1, secureNote, card, identity, sshKey, bankAccount, driversLicense, passport

    /// The order of the Type tiles in the sidebar.
    static let sidebarOrder: [ItemKind] = [.login, .card, .identity, .secureNote, .sshKey,
                                           .bankAccount, .driversLicense, .passport]

    var title: String {
        switch self {
        case .login: return "Login"
        case .secureNote: return "Secure Note"
        case .card: return "Card"
        case .identity: return "Identity"
        case .sshKey: return "SSH Key"
        case .bankAccount: return "Bank Account"
        case .driversLicense: return "Driver's License"
        case .passport: return "Passport"
        }
    }

    var icon: String {
        switch self {
        case .login: return "globe"
        case .secureNote: return "note.text"
        case .card: return "creditcard.fill"
        case .identity: return "person.text.rectangle.fill"
        case .sshKey: return "terminal.fill"
        case .bankAccount: return "building.columns.fill"
        case .driversLicense: return "car.fill"
        case .passport: return "airplane"
        }
    }

    /// The name of the item's data object on the server.
    var jsonKey: String {
        switch self {
        case .login: return "login"
        case .secureNote: return "secureNote"
        case .card: return "card"
        case .identity: return "identity"
        case .sshKey: return "sshKey"
        case .bankAccount: return "bankAccount"
        case .driversLicense: return "driversLicense"
        case .passport: return "passport"
        }
    }

    /// Fields that must have a value. Vaultwarden 1.37.5 treats an SSH key that lacks its fingerprint, public key or
    /// private key as invalid and sends it to every app without any data (src/db/models/cipher.rs).
    var requiredKeys: [String] {
        self == .sshKey ? ["keyFingerprint", "publicKey", "privateKey"] : []
    }

    /// The label of the first required field that is empty in `data`, if there is one.
    func missingField(in data: [String: String]) -> String? {
        schema.first { requiredKeys.contains($0.key)
            && (data[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }?.label
    }

    /// A line under the form when the kind has required fields.
    var requiredHint: String? {
        requiredKeys.isEmpty ? nil : "The server needs all of: " + schema.filter { requiredKeys.contains($0.key) }
            .map(\.label).joined(separator: ", ") + "."
    }

    /// The fields of the kinds that have a list of them (not logins, which are handled one by one, and secure
    /// notes, which are only a note). The names are the ones the Bitwarden apps use.
    var schema: [FieldSpec] {
        let date = "YYYY-MM-DD"
        switch self {
        case .login, .secureNote:
            return []
        case .card:
            return [FieldSpec(key: "cardholderName", label: "Cardholder Name"),
                    FieldSpec(key: "brand", label: "Brand", placeholder: "Visa"),
                    FieldSpec(key: "number", label: "Number", secret: true),
                    FieldSpec(key: "expMonth", label: "Expiration Month", placeholder: "MM"),
                    FieldSpec(key: "expYear", label: "Expiration Year", placeholder: "YYYY"),
                    FieldSpec(key: "code", label: "Security Code", secret: true)]
        case .identity:
            return [FieldSpec(key: "title", label: "Title"),
                    FieldSpec(key: "firstName", label: "First Name"),
                    FieldSpec(key: "middleName", label: "Middle Name"),
                    FieldSpec(key: "lastName", label: "Last Name"),
                    FieldSpec(key: "username", label: "User Name"),
                    FieldSpec(key: "company", label: "Company"),
                    FieldSpec(key: "ssn", label: "Social Security Number", secret: true),
                    FieldSpec(key: "passportNumber", label: "Passport Number", secret: true),
                    FieldSpec(key: "licenseNumber", label: "License Number", secret: true),
                    FieldSpec(key: "email", label: "Email"),
                    FieldSpec(key: "phone", label: "Phone"),
                    FieldSpec(key: "address1", label: "Address 1"),
                    FieldSpec(key: "address2", label: "Address 2"),
                    FieldSpec(key: "address3", label: "Address 3"),
                    FieldSpec(key: "city", label: "City / Town"),
                    FieldSpec(key: "state", label: "State / Province"),
                    FieldSpec(key: "postalCode", label: "Zip / Postal Code"),
                    FieldSpec(key: "country", label: "Country")]
        case .sshKey:
            return [FieldSpec(key: "keyFingerprint", label: "Fingerprint"),
                    FieldSpec(key: "publicKey", label: "Public Key", multiline: true),
                    FieldSpec(key: "privateKey", label: "Private Key", secret: true, multiline: true)]
        case .bankAccount:
            return [FieldSpec(key: "bankName", label: "Bank Name"),
                    FieldSpec(key: "nameOnAccount", label: "Name on Account"),
                    FieldSpec(key: "accountType", label: "Account Type", placeholder: "Checking"),
                    FieldSpec(key: "accountNumber", label: "Account Number", secret: true),
                    FieldSpec(key: "routingNumber", label: "Routing Number"),
                    FieldSpec(key: "branchNumber", label: "Branch Number"),
                    FieldSpec(key: "pin", label: "PIN", secret: true),
                    FieldSpec(key: "swiftCode", label: "SWIFT Code"),
                    FieldSpec(key: "iban", label: "IBAN", secret: true),
                    FieldSpec(key: "bankContactPhone", label: "Bank Contact Phone")]
        case .driversLicense:
            return [FieldSpec(key: "firstName", label: "First Name"),
                    FieldSpec(key: "middleName", label: "Middle Name"),
                    FieldSpec(key: "lastName", label: "Last Name"),
                    FieldSpec(key: "dateOfBirth", label: "Date of Birth", placeholder: date),
                    FieldSpec(key: "licenseNumber", label: "License Number", secret: true),
                    FieldSpec(key: "issuingCountry", label: "Issuing Country"),
                    FieldSpec(key: "issuingState", label: "Issuing State"),
                    FieldSpec(key: "issueDate", label: "Issue Date", placeholder: date),
                    FieldSpec(key: "expirationDate", label: "Expiration Date", placeholder: date),
                    FieldSpec(key: "issuingAuthority", label: "Issuing Authority"),
                    FieldSpec(key: "licenseClass", label: "License Class")]
        case .passport:
            return [FieldSpec(key: "surname", label: "Surname"),
                    FieldSpec(key: "givenName", label: "Given Name"),
                    FieldSpec(key: "dateOfBirth", label: "Date of Birth", placeholder: date),
                    FieldSpec(key: "sex", label: "Sex"),
                    FieldSpec(key: "birthPlace", label: "Birth Place"),
                    FieldSpec(key: "nationality", label: "Nationality"),
                    FieldSpec(key: "issuingCountry", label: "Issuing Country"),
                    FieldSpec(key: "passportNumber", label: "Passport Number", secret: true),
                    FieldSpec(key: "passportType", label: "Passport Type"),
                    FieldSpec(key: "nationalIdentificationNumber", label: "National ID Number", secret: true),
                    FieldSpec(key: "issuingAuthority", label: "Issuing Authority"),
                    FieldSpec(key: "issueDate", label: "Issue Date", placeholder: date),
                    FieldSpec(key: "expirationDate", label: "Expiration Date", placeholder: date)]
        }
    }
}

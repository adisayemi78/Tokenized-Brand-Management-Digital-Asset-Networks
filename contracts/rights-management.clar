;; Rights Management Contract
;; Manages asset access rights and permissions

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u400))
(define-constant err-not-found (err u401))
(define-constant err-unauthorized (err u402))
(define-constant err-expired (err u403))
(define-constant err-invalid-input (err u404))

;; Data Variables
(define-data-var next-permission-id uint u1)

;; Data Maps
(define-map asset-permissions
  { asset-id: uint, user: principal }
  {
    permission-level: (string-ascii 20),
    granted-by: principal,
    granted-at: uint,
    expires-at: uint,
    active: bool
  }
)

(define-map permission-templates
  { template-id: uint }
  {
    name: (string-ascii 50),
    permissions: (list 10 (string-ascii 20)),
    default-duration: uint,
    created-by: principal
  }
)

(define-map asset-rights
  { asset-id: uint }
  {
    owner: principal,
    license-type: (string-ascii 30),
    commercial-use: bool,
    modification-allowed: bool,
    redistribution-allowed: bool,
    attribution-required: bool
  }
)

(define-map user-roles
  { user: principal }
  {
    role: (string-ascii 20),
    permissions: (list 20 (string-ascii 20)),
    assigned-by: principal,
    assigned-at: uint
  }
)

;; Public Functions

;; Set asset rights
(define-public (set-asset-rights
  (asset-id uint)
  (license-type (string-ascii 30))
  (commercial-use bool)
  (modification-allowed bool)
  (redistribution-allowed bool)
  (attribution-required bool)
)
  (begin
    (map-set asset-rights
      { asset-id: asset-id }
      {
        owner: tx-sender,
        license-type: license-type,
        commercial-use: commercial-use,
        modification-allowed: modification-allowed,
        redistribution-allowed: redistribution-allowed,
        attribution-required: attribution-required
      }
    )
    (ok true)
  )
)

;; Grant permission to user for specific asset
(define-public (grant-permission
  (asset-id uint)
  (user principal)
  (permission-level (string-ascii 20))
  (duration uint)
)
  (let ((asset-rights-data (map-get? asset-rights { asset-id: asset-id })))
    (asserts! (or (is-eq tx-sender contract-owner)
                  (match asset-rights-data
                    rights (is-eq tx-sender (get owner rights))
                    false)) err-unauthorized)

    (map-set asset-permissions
      { asset-id: asset-id, user: user }
      {
        permission-level: permission-level,
        granted-by: tx-sender,
        granted-at: block-height,
        expires-at: (+ block-height duration),
        active: true
      }
    )
    (ok true)
  )
)

;; Revoke permission
(define-public (revoke-permission (asset-id uint) (user principal))
  (let ((permission (unwrap! (map-get? asset-permissions { asset-id: asset-id, user: user }) err-not-found))
        (asset-rights-data (map-get? asset-rights { asset-id: asset-id })))

    (asserts! (or (is-eq tx-sender contract-owner)
                  (is-eq tx-sender (get granted-by permission))
                  (match asset-rights-data
                    rights (is-eq tx-sender (get owner rights))
                    false)) err-unauthorized)

    (map-set asset-permissions
      { asset-id: asset-id, user: user }
      (merge permission { active: false })
    )
    (ok true)
  )
)

;; Assign role to user
(define-public (assign-role
  (user principal)
  (role (string-ascii 20))
  (permissions (list 20 (string-ascii 20)))
)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)

    (map-set user-roles
      { user: user }
      {
        role: role,
        permissions: permissions,
        assigned-by: tx-sender,
        assigned-at: block-height
      }
    )
    (ok true)
  )
)

;; Check if user has permission for asset
(define-public (check-permission (asset-id uint) (user principal) (required-permission (string-ascii 20)))
  (let ((permission (map-get? asset-permissions { asset-id: asset-id, user: user }))
        (user-role (map-get? user-roles { user: user })))

    ;; Check direct permission
    (match permission
      perm (if (and (get active perm)
                    (< block-height (get expires-at perm))
                    (is-eq (get permission-level perm) required-permission))
             (ok true)
             ;; Check role-based permission
             (match user-role
               role (ok (is-some (index-of (get permissions role) required-permission)))
               (ok false)))
      ;; Check role-based permission only
      (match user-role
        role (ok (is-some (index-of (get permissions role) required-permission)))
        (ok false))
    )
  )
)

;; Read-only Functions

;; Get asset rights
(define-read-only (get-asset-rights (asset-id uint))
  (map-get? asset-rights { asset-id: asset-id })
)

;; Get user permission for asset
(define-read-only (get-user-permission (asset-id uint) (user principal))
  (map-get? asset-permissions { asset-id: asset-id, user: user })
)

;; Get user role
(define-read-only (get-user-role (user principal))
  (map-get? user-roles { user: user })
)

;; Check if permission is valid (not expired)
(define-read-only (is-permission-valid (asset-id uint) (user principal))
  (match (map-get? asset-permissions { asset-id: asset-id, user: user })
    permission (and (get active permission) (< block-height (get expires-at permission)))
    false
  )
)

;; Check if user can perform commercial use
(define-read-only (can-commercial-use (asset-id uint) (user principal))
  (match (map-get? asset-rights { asset-id: asset-id })
    rights (and (get commercial-use rights) (is-permission-valid asset-id user))
    false
  )
)

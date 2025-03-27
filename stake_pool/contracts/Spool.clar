;; Decentralized Staking Protocol Contract - v1.0
;; Basic staking functionality with minimal validator system

(define-constant protocol-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-signature (err u101))
(define-constant err-paused (err u102))

;; Data Variables
(define-data-var protocol-paused bool false)
(define-map validators principal bool)
(define-map stake-registry 
    uint 
    {staker: principal, 
     asset-id: (string-ascii 64),
     timestamp: uint,
     processed: bool})

(define-data-var registry-index uint u0)

;; Read-only functions
(define-read-only (is-paused)
    (var-get protocol-paused))

(define-read-only (is-validator (validator principal))
    (default-to false (map-get? validators validator)))

;; Public functions
(define-public (register-validator (new-validator principal))
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (ok (map-set validators new-validator true))))

(define-public (toggle-pause)
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (ok (var-set protocol-paused (not (var-get protocol-paused))))))

(define-public (submit-stake (asset-id (string-ascii 64)))
    (let
        ((staker tx-sender))
        (asserts! (not (var-get protocol-paused)) err-paused)
        (map-set stake-registry
            (var-get registry-index)
            {staker: staker,
             asset-id: asset-id,
             timestamp: block-height,
             processed: false})
        (var-set registry-index (+ (var-get registry-index) u1))
        (ok true)))

(define-public (process-stake (registry-id uint))
    (let ((stake (unwrap-panic (map-get? stake-registry registry-id)))
          (validator tx-sender))
        (asserts! (not (var-get protocol-paused)) err-paused)
        (asserts! (is-validator validator) err-owner-only)
        (asserts! (not (get processed stake)) err-invalid-signature)
        
        ;; Process the stake
        (map-set stake-registry
            registry-id
            (merge stake {processed: true}))
        
        (ok true)))

;; Initialize contract
(begin
    ;; Register contract owner as first validator
    (try! (register-validator tx-sender))
    ;; Contract successfully initialized
    (ok true))
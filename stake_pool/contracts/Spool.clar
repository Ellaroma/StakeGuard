;; Decentralized Staking Protocol Contract - v2.0
;; Enhanced security with nonce tracking and validator reputation

(define-constant protocol-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-signature (err u101))
(define-constant err-invalid-nonce (err u102))
(define-constant err-paused (err u103))
(define-constant err-unauthorized-validator (err u104))

;; Data Variables
(define-data-var protocol-paused bool false)
(define-map nonce-tracker principal uint)
(define-map validators principal {reputation: uint, active: bool})
(define-map stake-registry 
    uint 
    {staker: principal, 
     asset-id: (string-ascii 64),
     nonce: uint,
     timestamp: uint,
     processed: bool})

(define-data-var registry-index uint u0)

;; Read-only functions
(define-read-only (get-nonce (user principal))
    (default-to u0 (map-get? nonce-tracker user)))

(define-read-only (is-paused)
    (var-get protocol-paused))

(define-read-only (get-validator-profile (validator principal))
    (map-get? validators validator))

;; Private functions
(define-private (increment-nonce (user principal))
    (let ((current-nonce (get-nonce user)))
        (map-set nonce-tracker 
            user 
            (+ current-nonce u1))))

(define-private (update-validator-reputation (validator principal))
    (let ((current-metrics (unwrap-panic (get-validator-profile validator))))
        (map-set validators
            validator
            (merge current-metrics {reputation: (+ (get reputation current-metrics) u1)}))))

;; Public functions
(define-public (register-validator (new-validator principal))
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (ok (map-set validators
            new-validator
            {reputation: u0,
             active: true}))))

(define-public (toggle-pause)
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (ok (var-set protocol-paused (not (var-get protocol-paused))))))

(define-public (deactivate-validator (target-validator principal))
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (let ((validator-data (unwrap-panic (get-validator-profile target-validator))))
            (ok (map-set validators
                target-validator
                (merge validator-data {active: false}))))))

(define-public (submit-stake (asset-id (string-ascii 64)))
    (let
        ((staker tx-sender)
         (current-nonce (get-nonce staker)))
        (asserts! (not (var-get protocol-paused)) err-paused)
        (map-set stake-registry
            (var-get registry-index)
            {staker: staker,
             asset-id: asset-id,
             nonce: current-nonce,
             timestamp: block-height,
             processed: false})
        (var-set registry-index (+ (var-get registry-index) u1))
        (ok true)))

(define-public (process-stake (registry-id uint))
    (let ((stake (unwrap-panic (map-get? stake-registry registry-id)))
          (validator tx-sender)
          (validator-data (unwrap! (get-validator-profile validator) err-unauthorized-validator)))
        (asserts! (not (var-get protocol-paused)) err-paused)
        (asserts! (get active validator-data) err-unauthorized-validator)
        (asserts! (not (get processed stake)) err-invalid-nonce)
        
        ;; Process the stake
        (map-set stake-registry
            registry-id
            (merge stake {processed: true}))
        
        ;; Update nonce and validator stats
        (increment-nonce (get staker stake))
        (update-validator-reputation validator)
        (ok true)))

;; Initialize contract
(begin
    ;; Register contract owner as first validator
    (try! (register-validator tx-sender))
    ;; Contract successfully initialized
    (ok true))
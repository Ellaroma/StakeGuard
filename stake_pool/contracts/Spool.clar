;; Decentralized Staking Protocol Contract - v3.0
;; Final implementation with cryptographic verification and advanced metrics

(define-constant protocol-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-invalid-signature (err u101))
(define-constant err-invalid-nonce (err u102))
(define-constant err-paused (err u103))
(define-constant err-unauthorized-validator (err u104))
(define-constant err-request-expired (err u105))
(define-constant err-insufficient-stake (err u106))
(define-constant err-invalid-parameter (err u107))

;; Data Variables
(define-data-var protocol-paused bool false)
(define-map nonce-tracker principal uint)
(define-map validators principal {reputation: uint, total-stakes: uint, active: bool, min-stake: uint})
(define-map stake-registry 
    uint 
    {staker: principal, 
     asset-id: (string-ascii 64),
     nonce: uint,
     timestamp: uint,
     signature: (buff 65),
     amount: uint,
     processed: bool})

(define-data-var registry-index uint u0)
(define-data-var expiry-blocks uint u144) ;; Default 24 hours (144 blocks)
(define-data-var max-min-stake uint u1000000) ;; Set a reasonable upper limit for minimum stake

;; Read-only functions
(define-read-only (get-nonce (user principal))
    (default-to u0 (map-get? nonce-tracker user)))

(define-read-only (is-paused)
    (var-get protocol-paused))

(define-read-only (get-validator-profile (validator principal))
    (map-get? validators validator))

(define-read-only (get-stake-details (stake-id uint))
    (map-get? stake-registry stake-id))

(define-read-only (get-protocol-stats)
    {total-stakes: (var-get registry-index),
     is-paused: (var-get protocol-paused),
     expiry-blocks: (var-get expiry-blocks),
     max-min-stake: (var-get max-min-stake)})

;; Read-only functions for signature verification
(define-read-only (verify-signature (message (buff 32)) (signature (buff 65)) (staker principal))
    (let ((recovered-public-key (unwrap! (secp256k1-recover? message signature) false)))
        (is-eq (unwrap! (principal-of? recovered-public-key) false) staker)))

;; Private functions
(define-private (increment-nonce (user principal))
    (let ((current-nonce (get-nonce user)))
        (map-set nonce-tracker 
            user 
            (+ current-nonce u1))))

(define-private (update-validator-metrics (validator principal) (stake-amount uint))
    (let ((current-metrics (unwrap-panic (get-validator-profile validator))))
        (map-set validators
            validator
            {reputation: (+ (get reputation current-metrics) u1),
             total-stakes: (+ (get total-stakes current-metrics) stake-amount),
             active: (get active current-metrics),
             min-stake: (get min-stake current-metrics)})))

(define-private (validate-principal (principal-to-check principal))
    (is-some (get-validator-profile principal-to-check)))

(define-private (validate-min-stake (min-stake uint))
    (<= min-stake (var-get max-min-stake)))

(define-private (validate-expiry (expiry uint))
    (and (> expiry u0) (<= expiry u1000)))

;; Public functions
(define-public (register-validator (new-validator principal) (minimum-stake uint))
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (asserts! (not (validate-principal new-validator)) err-invalid-parameter)
        (asserts! (validate-min-stake minimum-stake) err-invalid-parameter)
        (ok (map-set validators
            new-validator
            {reputation: u0,
             total-stakes: u0,
             active: true,
             min-stake: minimum-stake}))))

(define-public (toggle-pause)
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (ok (var-set protocol-paused (not (var-get protocol-paused))))))

(define-public (set-expiry-blocks (new-expiry uint))
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (asserts! (validate-expiry new-expiry) err-invalid-parameter)
        (ok (var-set expiry-blocks new-expiry))))

(define-public (set-max-min-stake (new-max-min-stake uint))
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (asserts! (> new-max-min-stake u0) err-invalid-parameter)
        (ok (var-set max-min-stake new-max-min-stake))))

(define-public (update-validator-status (target-validator principal) (active-status bool) (minimum-stake uint))
    (begin
        (asserts! (is-eq protocol-owner tx-sender) err-owner-only)
        (asserts! (validate-principal target-validator) err-invalid-parameter)
        (asserts! (validate-min-stake minimum-stake) err-invalid-parameter)
        (let ((validator-data (unwrap-panic (get-validator-profile target-validator))))
            (ok (map-set validators
                target-validator
                (merge validator-data 
                       {active: active-status,
                        min-stake: minimum-stake}))))))

(define-public (submit-stake 
    (asset-id (string-ascii 64))
    (signature (buff 65))
    (amount uint))
    (let
        ((staker tx-sender)
         (current-nonce (get-nonce staker))
         (message-hash (sha256 (concat (unwrap-panic (to-consensus-buff? asset-id))
                                     (concat (unwrap-panic (to-consensus-buff? current-nonce))
                                             (unwrap-panic (to-consensus-buff? amount)))))))
        (asserts! (not (var-get protocol-paused)) err-paused)
        (asserts! (> amount u0) err-invalid-parameter)
        (asserts! (verify-signature message-hash signature staker) err-invalid-signature)
        (map-set stake-registry
            (var-get registry-index)
            {staker: staker,
             asset-id: asset-id,
             nonce: current-nonce,
             timestamp: block-height,
             signature: signature,
             amount: amount,
             processed: false})
        (var-set registry-index (+ (var-get registry-index) u1))
        (ok true)))

(define-public (process-stake (registry-id uint))
    (let ((stake (unwrap-panic (map-get? stake-registry registry-id)))
          (validator tx-sender)
          (validator-data (unwrap! (get-validator-profile validator) err-unauthorized-validator))
          (current-height block-height))
        (asserts! (not (var-get protocol-paused)) err-paused)
        (asserts! (get active validator-data) err-unauthorized-validator)
        (asserts! (not (get processed stake)) err-invalid-nonce)
        (asserts! (<= (- current-height (get timestamp stake)) (var-get expiry-blocks)) err-request-expired)
        (asserts! (>= (get amount stake) (get min-stake validator-data)) err-insufficient-stake)
        
        ;; Process the stake
        (map-set stake-registry
            registry-id
            (merge stake {processed: true}))
        
        ;; Update nonce and validator stats
        (increment-nonce (get staker stake))
        (update-validator-metrics validator (get amount stake))
        (ok true)))

(define-public (cancel-stake (registry-id uint))
    (let ((stake (unwrap-panic (map-get? stake-registry registry-id)))
          (staker tx-sender))
        (asserts! (is-eq staker (get staker stake)) err-owner-only)
        (asserts! (not (get processed stake)) err-invalid-nonce)
        
        ;; Cancel the stake
        (map-set stake-registry
            registry-id
            (merge stake {processed: true}))
        
        ;; Update nonce
        (increment-nonce staker)
        (ok true)))

;; Initialize contract
(begin
    ;; Register contract owner as first validator with minimum stake of 10
    (try! (register-validator tx-sender u10))
    ;; Contract successfully initialized
    (ok true))
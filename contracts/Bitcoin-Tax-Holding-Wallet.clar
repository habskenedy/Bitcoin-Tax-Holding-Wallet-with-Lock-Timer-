(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-locked (err u101))
(define-constant err-not-locked (err u102))
(define-constant err-lock-in-future (err u103))
(define-constant err-before-unlock (err u104))
(define-constant err-no-value (err u105))

(define-data-var tax-rate uint u30)
(define-data-var unlock-height uint u0)

(define-map tax-deposits
    principal
    {
        amount: uint,
        locked-until: uint,
    }
)

(define-public (set-tax-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set tax-rate new-rate)
        (ok true)
    )
)

(define-read-only (get-tax-rate)
    (ok (var-get tax-rate))
)

(define-read-only (get-deposit (wallet principal))
    (match (map-get? tax-deposits wallet)
        existing-deposit (ok existing-deposit)
        (ok {
            amount: u0,
            locked-until: u0,
        })
    )
)

(define-public (deposit
        (amount uint)
        (lock-until uint)
    )
    (let ((current-height burn-block-height))
        (asserts! (> amount u0) err-no-value)
        (asserts! (> lock-until current-height) err-lock-in-future)
        (match (map-get? tax-deposits tx-sender)
            existing-deposit (begin
                (asserts! (is-eq (get locked-until existing-deposit) u0)
                    err-already-locked
                )
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                (map-set tax-deposits tx-sender {
                    amount: (+ amount (get amount existing-deposit)),
                    locked-until: lock-until,
                })
            )
            (begin
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                (map-set tax-deposits tx-sender {
                    amount: amount,
                    locked-until: lock-until,
                })
            )
        )
        (ok true)
    )
)

(define-public (withdraw (amount uint))
    (let (
            (current-height burn-block-height)
            (deposit-data (unwrap! (map-get? tax-deposits tx-sender) err-not-locked))
        )
        (asserts! (>= current-height (get locked-until deposit-data))
            err-before-unlock
        )
        (asserts! (<= amount (get amount deposit-data)) err-no-value)
        (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))
        (if (< amount (get amount deposit-data))
            (map-set tax-deposits tx-sender {
                amount: (- (get amount deposit-data) amount),
                locked-until: (get locked-until deposit-data),
            })
            (map-delete tax-deposits tx-sender)
        )
        (ok true)
    )
)

(define-read-only (get-balance (wallet principal))
    (match (map-get? tax-deposits wallet)
        deposit-data (ok (get amount deposit-data))
        (ok u0)
    )
)

(define-read-only (get-unlock-height (wallet principal))
    (match (map-get? tax-deposits wallet)
        deposit-data (ok (get locked-until deposit-data))
        (ok u0)
    )
)

(define-public (emergency-withdraw)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (let ((balance (stx-get-balance (as-contract tx-sender))))
            (try! (as-contract (stx-transfer? balance (as-contract tx-sender) contract-owner)))
            (ok true)
        )
    )
)

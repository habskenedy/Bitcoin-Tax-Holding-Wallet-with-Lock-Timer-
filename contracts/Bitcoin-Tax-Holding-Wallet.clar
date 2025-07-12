(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-locked (err u101))
(define-constant err-not-locked (err u102))
(define-constant err-lock-in-future (err u103))
(define-constant err-before-unlock (err u104))
(define-constant err-no-value (err u105))
(define-constant err-no-interest (err u106))

(define-data-var tax-rate uint u30)
(define-data-var unlock-height uint u0)
(define-data-var annual-interest-rate uint u5)

(define-map tax-deposits
    principal
    {
        amount: uint,
        locked-until: uint,
        deposit-height: uint,
        interest-earned: uint,
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

(define-public (set-interest-rate (new-rate uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set annual-interest-rate new-rate)
        (ok true)
    )
)

(define-read-only (get-interest-rate)
    (ok (var-get annual-interest-rate))
)

(define-private (calculate-interest (principal-amount uint) (blocks-held uint))
    (let ((annual-rate (var-get annual-interest-rate)))
        (/ (* (* principal-amount annual-rate) blocks-held) u525600)
    )
)

(define-read-only (get-deposit (wallet principal))
    (match (map-get? tax-deposits wallet)
        existing-deposit (ok existing-deposit)
        (ok {
            amount: u0,
            locked-until: u0,
            deposit-height: u0,
            interest-earned: u0,
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
                    deposit-height: current-height,
                    interest-earned: u0,
                })
            )
            (begin
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                (map-set tax-deposits tx-sender {
                    amount: amount,
                    locked-until: lock-until,
                    deposit-height: current-height,
                    interest-earned: u0,
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
            (blocks-held (- current-height (get deposit-height deposit-data)))
            (interest-earned (calculate-interest (get amount deposit-data) blocks-held))
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
                deposit-height: (get deposit-height deposit-data),
                interest-earned: interest-earned,
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

(define-public (claim-interest)
    (let (
            (current-height burn-block-height)
            (deposit-data (unwrap! (map-get? tax-deposits tx-sender) err-not-locked))
            (blocks-held (- current-height (get deposit-height deposit-data)))
            (interest-earned (calculate-interest (get amount deposit-data) blocks-held))
        )
        (asserts! (> interest-earned u0) err-no-interest)
        (try! (as-contract (stx-transfer? interest-earned (as-contract tx-sender) tx-sender)))
        (map-set tax-deposits tx-sender {
            amount: (get amount deposit-data),
            locked-until: (get locked-until deposit-data),
            deposit-height: current-height,
            interest-earned: u0,
        })
        (ok interest-earned)
    )
)

(define-read-only (get-accrued-interest (wallet principal))
    (match (map-get? tax-deposits wallet)
        deposit-data (let (
                (current-height burn-block-height)
                (blocks-held (- current-height (get deposit-height deposit-data)))
                (interest-earned (calculate-interest (get amount deposit-data) blocks-held))
            )
            (ok interest-earned)
        )
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

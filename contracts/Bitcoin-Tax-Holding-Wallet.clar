(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-already-locked (err u101))
(define-constant err-not-locked (err u102))
(define-constant err-lock-in-future (err u103))
(define-constant err-before-unlock (err u104))
(define-constant err-no-value (err u105))
(define-constant err-no-interest (err u106))
(define-constant err-insufficient-amount (err u107))

(define-constant fee-tier-1 u300)
(define-constant fee-tier-2 u200)
(define-constant fee-tier-3 u100)
(define-constant fee-tier-4 u50)
(define-constant early-withdrawal-penalty u1500)

(define-data-var tax-rate uint u30)
(define-data-var total-fees-collected uint u0)
(define-data-var unlock-height uint u0)
(define-data-var annual-interest-rate uint u5)
(define-data-var total-penalties-collected uint u0)
(define-data-var compliance-report-counter uint u0)

;; Tax compliance tracking maps
(define-map transaction-history
    {
        user: principal,
        tx-id: uint,
    }
    {
        tx-type: (string-ascii 20),
        amount: uint,
        timestamp: uint,
        block-height: uint,
        fees-paid: uint,
        penalty-paid: uint,
    }
)

(define-map annual-tax-summary
    {
        user: principal,
        year: uint,
    }
    {
        total-deposits: uint,
        total-withdrawals: uint,
        total-fees-paid: uint,
        total-penalties-paid: uint,
        total-interest-earned: uint,
        transaction-count: uint,
    }
)

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

(define-private (calculate-withdrawal-fee
        (lock-duration uint)
        (amount uint)
    )
    (let ((fee-basis-points (if (>= lock-duration u52560)
            fee-tier-4
            (if (>= lock-duration u26280)
                fee-tier-3
                (if (>= lock-duration u13140)
                    fee-tier-2
                    fee-tier-1
                )
            )
        )))
        (/ (* amount fee-basis-points) u10000)
    )
)

(define-private (calculate-early-withdrawal-penalty (amount uint))
    (/ (* amount early-withdrawal-penalty) u10000)
)

(define-read-only (get-total-fees-collected)
    (ok (var-get total-fees-collected))
)

(define-read-only (get-total-penalties-collected)
    (ok (var-get total-penalties-collected))
)

(define-private (calculate-interest
        (principal-amount uint)
        (blocks-held uint)
    )
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
                (record-transaction tx-sender "deposit" amount u0 u0)
            )
            (begin
                (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
                (map-set tax-deposits tx-sender {
                    amount: amount,
                    locked-until: lock-until,
                    deposit-height: current-height,
                    interest-earned: u0,
                })
                (record-transaction tx-sender "deposit" amount u0 u0)
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
            (lock-duration (- (get locked-until deposit-data) (get deposit-height deposit-data)))
            (withdrawal-fee (calculate-withdrawal-fee lock-duration amount))
            (net-amount (- amount withdrawal-fee))
        )
        (asserts! (>= current-height (get locked-until deposit-data))
            err-before-unlock
        )
        (asserts! (<= amount (get amount deposit-data)) err-no-value)
        (asserts! (> net-amount u0) err-insufficient-amount)
        (try! (as-contract (stx-transfer? net-amount (as-contract tx-sender) tx-sender)))
        (var-set total-fees-collected
            (+ (var-get total-fees-collected) withdrawal-fee)
        )
        (if (< amount (get amount deposit-data))
            (map-set tax-deposits tx-sender {
                amount: (- (get amount deposit-data) amount),
                locked-until: (get locked-until deposit-data),
                deposit-height: (get deposit-height deposit-data),
                interest-earned: interest-earned,
            })
            (map-delete tax-deposits tx-sender)
        )
        (record-transaction tx-sender "withdraw" amount withdrawal-fee u0)
        (ok net-amount)
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
        (record-transaction tx-sender "claim-interest" interest-earned u0 u0)
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

(define-read-only (preview-withdrawal-fee
        (wallet principal)
        (amount uint)
    )
    (match (map-get? tax-deposits wallet)
        deposit-data (let (
                (lock-duration (- (get locked-until deposit-data)
                    (get deposit-height deposit-data)
                ))
                (withdrawal-fee (calculate-withdrawal-fee lock-duration amount))
            )
            (ok withdrawal-fee)
        )
        (ok u0)
    )
)

(define-public (early-withdraw (amount uint))
    (let (
            (current-height burn-block-height)
            (deposit-data (unwrap! (map-get? tax-deposits tx-sender) err-not-locked))
            (penalty (calculate-early-withdrawal-penalty amount))
            (net-amount (- amount penalty))
        )
        (asserts! (< current-height (get locked-until deposit-data))
            err-not-locked
        )
        (asserts! (<= amount (get amount deposit-data)) err-no-value)
        (asserts! (> net-amount u0) err-insufficient-amount)
        (try! (as-contract (stx-transfer? net-amount (as-contract tx-sender) tx-sender)))
        (var-set total-penalties-collected
            (+ (var-get total-penalties-collected) penalty)
        )
        (if (< amount (get amount deposit-data))
            (map-set tax-deposits tx-sender {
                amount: (- (get amount deposit-data) amount),
                locked-until: (get locked-until deposit-data),
                deposit-height: (get deposit-height deposit-data),
                interest-earned: (get interest-earned deposit-data),
            })
            (map-delete tax-deposits tx-sender)
        )
        (record-transaction tx-sender "early-withdraw" amount u0 penalty)
        (ok net-amount)
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

;; === TAX COMPLIANCE REPORTING FUNCTIONS ===

;; Helper function to record transactions for compliance
(define-private (record-transaction
        (user principal)
        (tx-type (string-ascii 20))
        (amount uint)
        (fees uint)
        (penalty uint)
    )
    (let (
            (current-tx-id (+ (var-get compliance-report-counter) u1))
            (current-year (/ burn-block-height u52560))
        )
        (var-set compliance-report-counter current-tx-id)
        (map-set transaction-history {
            user: user,
            tx-id: current-tx-id,
        } {
            tx-type: tx-type,
            amount: amount,
            timestamp: (unwrap-panic (get-stacks-block-info? time burn-block-height)),
            block-height: burn-block-height,
            fees-paid: fees,
            penalty-paid: penalty,
        })
        ;; Update annual summary
        (match (map-get? annual-tax-summary {
            user: user,
            year: current-year,
        })
            existing-summary (map-set annual-tax-summary {
                user: user,
                year: current-year,
            } {
                total-deposits: (if (is-eq tx-type "deposit")
                    (+ (get total-deposits existing-summary) amount)
                    (get total-deposits existing-summary)
                ),
                total-withdrawals: (if (or (is-eq tx-type "withdraw") (is-eq tx-type "early-withdraw"))
                    (+ (get total-withdrawals existing-summary) amount)
                    (get total-withdrawals existing-summary)
                ),
                total-fees-paid: (+ (get total-fees-paid existing-summary) fees),
                total-penalties-paid: (+ (get total-penalties-paid existing-summary) penalty),
                total-interest-earned: (if (is-eq tx-type "claim-interest")
                    (+ (get total-interest-earned existing-summary) amount)
                    (get total-interest-earned existing-summary)
                ),
                transaction-count: (+ (get transaction-count existing-summary) u1),
            })
            (map-set annual-tax-summary {
                user: user,
                year: current-year,
            } {
                total-deposits: (if (is-eq tx-type "deposit")
                    amount
                    u0
                ),
                total-withdrawals: (if (or (is-eq tx-type "withdraw") (is-eq tx-type "early-withdraw"))
                    amount
                    u0
                ),
                total-fees-paid: fees,
                total-penalties-paid: penalty,
                total-interest-earned: (if (is-eq tx-type "claim-interest")
                    amount
                    u0
                ),
                transaction-count: u1,
            })
        )
        current-tx-id
    )
)

;; Get transaction history for a specific user
(define-read-only (get-transaction-history
        (user principal)
        (tx-id uint)
    )
    (map-get? transaction-history {
        user: user,
        tx-id: tx-id,
    })
)

;; Get annual tax summary for a user
(define-read-only (get-annual-tax-summary
        (user principal)
        (year uint)
    )
    (map-get? annual-tax-summary {
        user: user,
        year: year,
    })
)

;; Generate comprehensive tax report for a user
(define-read-only (get-tax-compliance-report
        (user principal)
        (year uint)
    )
    (match (map-get? annual-tax-summary {
        user: user,
        year: year,
    })
        summary
        (let (
                (current-deposit (unwrap-panic (get-deposit user)))
                (current-interest (unwrap-panic (get-accrued-interest user)))
            )
            (ok {
                year: year,
                user: user,
                annual-summary: summary,
                current-deposit-balance: (get amount current-deposit),
                current-locked-until: (get locked-until current-deposit),
                current-accrued-interest: current-interest,
                report-generated-at: burn-block-height,
                net-tax-impact: (-
                    (+ (get total-deposits summary)
                        (get total-interest-earned summary)
                    )
                    (+ (get total-withdrawals summary)
                        (get total-fees-paid summary)
                        (get total-penalties-paid summary)
                    )),
            })
        )
        (err u404) ;; No data found for this year
    )
)

;; Get total compliance statistics (owner only)
(define-read-only (get-compliance-statistics)
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (ok {
            total-transactions-recorded: (var-get compliance-report-counter),
            total-fees-collected: (var-get total-fees-collected),
            total-penalties-collected: (var-get total-penalties-collected),
            current-tax-rate: (var-get tax-rate),
            current-interest-rate: (var-get annual-interest-rate),
        })
    )
)

;; Batch export user transactions for a range (owner only)
(define-read-only (export-user-transactions
        (user principal)
        (start-tx-id uint)
        (end-tx-id uint)
    )
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (<= start-tx-id end-tx-id) err-no-value)
        (ok {
            user: user,
            start-tx-id: start-tx-id,
            end-tx-id: end-tx-id,
            export-height: burn-block-height,
        })
    )
)

(define-constant err-no-beneficiary (err u108))
(define-constant err-not-beneficiary (err u109))
(define-constant err-inactive-window (err u110))

(define-map beneficiary-settings
    principal
    {
        beneficiary: principal,
        claimable-after: uint,
    }
)

(define-public (set-beneficiary
        (beneficiary principal)
        (inactivity-period uint)
    )
    (begin
        (asserts! (> inactivity-period u0) err-no-value)
        (map-set beneficiary-settings tx-sender {
            beneficiary: beneficiary,
            claimable-after: (+ burn-block-height inactivity-period),
        })
        (ok true)
    )
)

(define-public (clear-beneficiary)
    (begin
        (map-delete beneficiary-settings tx-sender)
        (ok true)
    )
)

(define-public (heartbeat (inactivity-period uint))
    (let ((settings (unwrap! (map-get? beneficiary-settings tx-sender) err-no-beneficiary)))
        (asserts! (> inactivity-period u0) err-no-value)
        (map-set beneficiary-settings tx-sender {
            beneficiary: (get beneficiary settings),
            claimable-after: (+ burn-block-height inactivity-period),
        })
        (ok true)
    )
)

(define-public (beneficiary-claim (owner principal))
    (let (
            (settings (unwrap! (map-get? beneficiary-settings owner) err-no-beneficiary))
            (current-height burn-block-height)
            (deposit-data (unwrap! (map-get? tax-deposits owner) err-not-locked))
            (amount (get amount deposit-data))
        )
        (asserts! (is-eq tx-sender (get beneficiary settings))
            err-not-beneficiary
        )
        (asserts! (>= current-height (get claimable-after settings))
            err-inactive-window
        )
        (asserts! (>= current-height (get locked-until deposit-data))
            err-before-unlock
        )
        (try! (as-contract (stx-transfer? amount (as-contract tx-sender) tx-sender)))
        (map-delete tax-deposits owner)
        (record-transaction owner "beneficiary-claim" amount u0 u0)
        (ok amount)
    )
)

(define-read-only (get-beneficiary (owner principal))
    (map-get? beneficiary-settings owner)
)

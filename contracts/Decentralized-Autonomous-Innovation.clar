;; Decentralized Autonomous Innovation (DAI) Platform
;; A blockchain-based ecosystem for autonomous innovation, funding, and collaboration
;; Version: 1.0.0
;; Compatible with: Clarinet 3.x

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u404))
(define-constant ERR_MILESTONE_NOT_FOUND (err u405))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_INVALID_PARAMETERS (err u400))
(define-constant ERR_ALREADY_VOTED (err u409))
(define-constant ERR_PROPOSAL_NOT_ACTIVE (err u408))
(define-constant ERR_MILESTONE_NOT_READY (err u407))
(define-constant ERR_FUNDING_COMPLETE (err u406))

;; Data Variables
(define-data-var proposal-counter uint u0)
(define-data-var milestone-counter uint u0)
(define-data-var innovation-fund uint u0)
(define-data-var platform-fee-percentage uint u5) ;; 5% platform fee
(define-data-var min-proposal-funding uint u10000) ;; Minimum funding goal in microSTX
(define-data-var voting-period uint u2016) ;; Voting period in blocks (~14 days)
(define-data-var governance-threshold uint u60) ;; 60% approval threshold

;; Status Constants
(define-constant STATUS_DRAFT u1)
(define-constant STATUS_FUNDING u2)
(define-constant STATUS_ACTIVE u3)
(define-constant STATUS_COMPLETED u4)
(define-constant STATUS_CANCELLED u5)

;; Data Maps
(define-map proposals 
    { proposal-id: uint }
    {
        innovator: principal,
        title: (string-ascii 128),
        description: (string-ascii 1024),
        category: (string-ascii 64),
        funding-goal: uint,
        funding-raised: uint,
        funding-deadline: uint,
        status: uint,
        milestone-count: uint,
        votes-for: uint,
        votes-against: uint,
        total-backers: uint,
        innovation-score: uint,
        created-at: uint
    }
)

(define-map milestones 
    { milestone-id: uint }
    {
        proposal-id: uint,
        title: (string-ascii 128),
        description: (string-ascii 512),
        funding-allocation: uint,
        completion-criteria: (string-ascii 256),
        evidence-hash: (optional (buff 32)),
        status: uint,
        votes-for: uint,
        votes-against: uint,
        created-at: uint,
        completed-at: (optional uint)
    }
)

(define-map proposal-backers
    { proposal-id: uint, backer: principal }
    {
        amount: uint,
        backed-at: uint,
        rewards-claimed: bool
    }
)

(define-map milestone-votes
    { milestone-id: uint, voter: principal }
    {
        vote: bool,
        voting-power: uint,
        voted-at: uint
    }
)

(define-map proposal-votes
    { proposal-id: uint, voter: principal }
    {
        vote: bool,
        voted-at: uint
    }
)

(define-map innovator-profiles
    { innovator: principal }
    {
        name: (string-ascii 64),
        bio: (string-ascii 256),
        expertise: (string-ascii 128),
        reputation-score: uint,
        proposals-created: uint,
        successful-innovations: uint,
        total-funding-raised: uint
    }
)

(define-map collaborations
    { proposal-id: uint, collaborator: principal }
    {
        role: (string-ascii 64),
        contribution-percentage: uint,
        joined-at: uint
    }
)

;; Public Functions

;; Create innovator profile
(define-public (create-innovator-profile 
    (name (string-ascii 64))
    (bio (string-ascii 256))
    (expertise (string-ascii 128)))
    (begin
        (asserts! (> (len name) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len expertise) u0) ERR_INVALID_PARAMETERS)
        
        (map-set innovator-profiles { innovator: tx-sender }
            {
                name: name,
                bio: bio,
                expertise: expertise,
                reputation-score: u0,
                proposals-created: u0,
                successful-innovations: u0,
                total-funding-raised: u0
            }
        )
        (ok true)
    )
)

;; Submit innovation proposal
(define-public (submit-proposal
    (title (string-ascii 128))
    (description (string-ascii 1024))
    (category (string-ascii 64))
    (funding-goal uint)
    (funding-period uint))
    (let 
        (
            (new-proposal-id (+ (var-get proposal-counter) u1))
            (funding-deadline (+ burn-block-height funding-period))
        )
        (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> (len description) u0) ERR_INVALID_PARAMETERS)
        (asserts! (>= funding-goal (var-get min-proposal-funding)) ERR_INVALID_PARAMETERS)
        (asserts! (> funding-period u0) ERR_INVALID_PARAMETERS)
        
        (map-set proposals { proposal-id: new-proposal-id }
            {
                innovator: tx-sender,
                title: title,
                description: description,
                category: category,
                funding-goal: funding-goal,
                funding-raised: u0,
                funding-deadline: funding-deadline,
                status: STATUS_FUNDING,
                milestone-count: u0,
                votes-for: u0,
                votes-against: u0,
                total-backers: u0,
                innovation-score: u0,
                created-at: burn-block-height
            }
        )
        
        ;; Update innovator profile
        (match (map-get? innovator-profiles { innovator: tx-sender })
            profile (map-set innovator-profiles { innovator: tx-sender }
                (merge profile { proposals-created: (+ (get proposals-created profile) u1) }))
            false
        )
        
        (var-set proposal-counter new-proposal-id)
        (ok new-proposal-id)
    )
)

;; Back a proposal with funding
(define-public (back-proposal (proposal-id uint) (amount uint))
    (let 
        (
            (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
            (current-backing (default-to { amount: u0, backed-at: u0, rewards-claimed: false }
                (map-get? proposal-backers { proposal-id: proposal-id, backer: tx-sender })))
        )
        (asserts! (is-eq (get status proposal) STATUS_FUNDING) ERR_PROPOSAL_NOT_ACTIVE)
        (asserts! (<= burn-block-height (get funding-deadline proposal)) ERR_PROPOSAL_NOT_ACTIVE)
        (asserts! (>= (stx-get-balance tx-sender) amount) ERR_INSUFFICIENT_FUNDS)
        (asserts! (> amount u0) ERR_INVALID_PARAMETERS)
        
        (let 
            (
                (new-total-raised (+ (get funding-raised proposal) amount))
                (is-new-backer (is-eq (get amount current-backing) u0))
            )
            (asserts! (<= new-total-raised (get funding-goal proposal)) ERR_FUNDING_COMPLETE)
            
            ;; Transfer funds to contract
            (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
            
            ;; Update proposal
            (map-set proposals { proposal-id: proposal-id }
                (merge proposal {
                    funding-raised: new-total-raised,
                    total-backers: (if is-new-backer 
                                      (+ (get total-backers proposal) u1)
                                      (get total-backers proposal)),
                    status: (if (is-eq new-total-raised (get funding-goal proposal))
                               STATUS_ACTIVE
                               STATUS_FUNDING)
                })
            )
            
            ;; Update backer record
            (map-set proposal-backers 
                { proposal-id: proposal-id, backer: tx-sender }
                {
                    amount: (+ (get amount current-backing) amount),
                    backed-at: (if is-new-backer burn-block-height (get backed-at current-backing)),
                    rewards-claimed: false
                }
            )
            
            ;; Update innovator's total funding raised
            (let ((innovator (get innovator proposal)))
                (match (map-get? innovator-profiles { innovator: innovator })
                    profile (map-set innovator-profiles { innovator: innovator }
                        (merge profile { 
                            total-funding-raised: (+ (get total-funding-raised profile) amount) 
                        }))
                    false
                )
            )
            
            (ok true)
        )
    )
)

;; Create milestone for active proposal
(define-public (create-milestone
    (proposal-id uint)
    (title (string-ascii 128))
    (description (string-ascii 512))
    (funding-allocation uint)
    (completion-criteria (string-ascii 256)))
    (let 
        (
            (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
            (new-milestone-id (+ (var-get milestone-counter) u1))
        )
        (asserts! (is-eq tx-sender (get innovator proposal)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status proposal) STATUS_ACTIVE) ERR_PROPOSAL_NOT_ACTIVE)
        (asserts! (> (len title) u0) ERR_INVALID_PARAMETERS)
        (asserts! (> funding-allocation u0) ERR_INVALID_PARAMETERS)
        
        (map-set milestones { milestone-id: new-milestone-id }
            {
                proposal-id: proposal-id,
                title: title,
                description: description,
                funding-allocation: funding-allocation,
                completion-criteria: completion-criteria,
                evidence-hash: none,
                status: STATUS_DRAFT,
                votes-for: u0,
                votes-against: u0,
                created-at: burn-block-height,
                completed-at: none
            }
        )
        
        ;; Update proposal milestone count
        (map-set proposals { proposal-id: proposal-id }
            (merge proposal { milestone-count: (+ (get milestone-count proposal) u1) })
        )
        
        (var-set milestone-counter new-milestone-id)
        (ok new-milestone-id)
    )
)

;; Submit milestone completion evidence
(define-public (complete-milestone 
    (milestone-id uint) 
    (evidence-hash (buff 32)))
    (let 
        (
            (milestone (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
            (proposal (unwrap! (map-get? proposals { proposal-id: (get proposal-id milestone) }) ERR_PROPOSAL_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender (get innovator proposal)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status milestone) STATUS_DRAFT) ERR_MILESTONE_NOT_READY)
        
        (map-set milestones { milestone-id: milestone-id }
            (merge milestone {
                evidence-hash: (some evidence-hash),
                status: STATUS_FUNDING,
                completed-at: (some burn-block-height)
            })
        )
        (ok true)
    )
)

;; Vote on milestone completion
(define-public (vote-milestone 
    (milestone-id uint) 
    (approve bool))
    (let 
        (
            (milestone (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
            (proposal (unwrap! (map-get? proposals { proposal-id: (get proposal-id milestone) }) ERR_PROPOSAL_NOT_FOUND))
            (backer-info (map-get? proposal-backers { proposal-id: (get proposal-id milestone), backer: tx-sender }))
        )
        (asserts! (is-some backer-info) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status milestone) STATUS_FUNDING) ERR_MILESTONE_NOT_READY)
        (asserts! (is-none (map-get? milestone-votes { milestone-id: milestone-id, voter: tx-sender })) ERR_ALREADY_VOTED)
        
        (let 
            (
                (voting-power (get amount (unwrap-panic backer-info)))
                (new-votes-for (if approve (+ (get votes-for milestone) voting-power) (get votes-for milestone)))
                (new-votes-against (if approve (get votes-against milestone) (+ (get votes-against milestone) voting-power)))
            )
            (map-set milestone-votes 
                { milestone-id: milestone-id, voter: tx-sender }
                {
                    vote: approve,
                    voting-power: voting-power,
                    voted-at: burn-block-height
                }
            )
            
            (map-set milestones { milestone-id: milestone-id }
                (merge milestone {
                    votes-for: new-votes-for,
                    votes-against: new-votes-against,
                    status: (if (> (* new-votes-for u100) 
                                  (* (+ new-votes-for new-votes-against) (var-get governance-threshold)))
                               STATUS_ACTIVE
                               STATUS_FUNDING)
                })
            )
            (ok true)
        )
    )
)

;; Release milestone funding
(define-public (release-milestone-funding (milestone-id uint))
    (let 
        (
            (milestone (unwrap! (map-get? milestones { milestone-id: milestone-id }) ERR_MILESTONE_NOT_FOUND))
            (proposal (unwrap! (map-get? proposals { proposal-id: (get proposal-id milestone) }) ERR_PROPOSAL_NOT_FOUND))
            (funding-amount (get funding-allocation milestone))
            (platform-fee (/ (* funding-amount (var-get platform-fee-percentage)) u100))
            (innovator-payment (- funding-amount platform-fee))
        )
        (asserts! (is-eq (get status milestone) STATUS_ACTIVE) ERR_MILESTONE_NOT_READY)
        
        ;; Transfer funds
        (try! (as-contract (stx-transfer? innovator-payment tx-sender (get innovator proposal))))
        (try! (as-contract (stx-transfer? platform-fee tx-sender CONTRACT_OWNER)))
        
        ;; Update milestone status
        (map-set milestones { milestone-id: milestone-id }
            (merge milestone { status: STATUS_COMPLETED })
        )
        
        ;; Update innovation fund
        (var-set innovation-fund (+ (var-get innovation-fund) platform-fee))
        
        (ok true)
    )
)

;; Add collaborator to proposal
(define-public (add-collaborator
    (proposal-id uint)
    (collaborator principal)
    (role (string-ascii 64))
    (contribution-percentage uint))
    (let 
        (
            (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
        )
        (asserts! (is-eq tx-sender (get innovator proposal)) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status proposal) STATUS_ACTIVE) ERR_PROPOSAL_NOT_ACTIVE)
        (asserts! (<= contribution-percentage u100) ERR_INVALID_PARAMETERS)
        
        (map-set collaborations 
            { proposal-id: proposal-id, collaborator: collaborator }
            {
                role: role,
                contribution-percentage: contribution-percentage,
                joined-at: burn-block-height
            }
        )
        (ok true)
    )
)

;; Vote on proposal governance
(define-public (vote-proposal 
    (proposal-id uint) 
    (approve bool))
    (let 
        (
            (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
        )
        (asserts! (is-some (map-get? proposal-backers { proposal-id: proposal-id, backer: tx-sender })) ERR_UNAUTHORIZED)
        (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: tx-sender })) ERR_ALREADY_VOTED)
        
        (map-set proposal-votes 
            { proposal-id: proposal-id, voter: tx-sender }
            {
                vote: approve,
                voted-at: burn-block-height
            }
        )
        
        (map-set proposals { proposal-id: proposal-id }
            (merge proposal {
                votes-for: (if approve (+ (get votes-for proposal) u1) (get votes-for proposal)),
                votes-against: (if approve (get votes-against proposal) (+ (get votes-against proposal) u1))
            })
        )
        (ok true)
    )
)

;; Read-only functions

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals { proposal-id: proposal-id })
)

(define-read-only (get-milestone (milestone-id uint))
    (map-get? milestones { milestone-id: milestone-id })
)

(define-read-only (get-innovator-profile (innovator principal))
    (map-get? innovator-profiles { innovator: innovator })
)

(define-read-only (get-backer-info (proposal-id uint) (backer principal))
    (map-get? proposal-backers { proposal-id: proposal-id, backer: backer })
)

(define-read-only (get-collaboration (proposal-id uint) (collaborator principal))
    (map-get? collaborations { proposal-id: proposal-id, collaborator: collaborator })
)

(define-read-only (get-proposal-counter)
    (var-get proposal-counter)
)

(define-read-only (get-milestone-counter)
    (var-get milestone-counter)
)

(define-read-only (get-innovation-fund)
    (var-get innovation-fund)
)

(define-read-only (get-platform-fee-percentage)
    (var-get platform-fee-percentage)
)

(define-read-only (get-governance-threshold)
    (var-get governance-threshold)
)

;; Admin functions (only contract owner)
(define-public (update-platform-fee (new-fee uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= new-fee u15) ERR_INVALID_PARAMETERS) ;; Max 15% fee
        (var-set platform-fee-percentage new-fee)
        (ok true)
    )
)

(define-public (update-governance-threshold (new-threshold uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (and (>= new-threshold u50) (<= new-threshold u90)) ERR_INVALID_PARAMETERS)
        (var-set governance-threshold new-threshold)
        (ok true)
    )
)

(define-public (distribute-innovation-rewards (amount uint) (recipient principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (asserts! (<= amount (var-get innovation-fund)) ERR_INSUFFICIENT_FUNDS)
        (try! (as-contract (stx-transfer? amount tx-sender recipient)))
        (var-set innovation-fund (- (var-get innovation-fund) amount))
        (ok true)
    )
)
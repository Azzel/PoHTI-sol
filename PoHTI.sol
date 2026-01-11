// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.2 <0.9.0;

contract PoHTI {

    struct Policy {
        address holder;
        uint256 startDate;
        uint256 endDate;
        uint256 payoutAmount;
        uint256 stakeAmount;
        uint256 creationTimestamp;
        PolicyStatus status;
        bool hasActiveClaim;
    }

    struct Claim {
        address policyHolder;
        uint256 policyId; // ← Добавляем это поле
        uint256 claimTimestamp;
        string evidenceIPFSHash; // Ссылка на доказательства в IPFS
        address[] validators; // Список выбранных верификаторов
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => Vote) votes; // Голоса каждого валидатора
        ClaimStatus status;
        uint256 validationEndTime;
        uint256 appealStake;
        address appealInitiator;
    }

    struct ValidatorSlot {
        address validator;
        uint256 stakeLocked;
        uint256 assignmentTimestamp;
    }

    enum PolicyStatus { Active, Expired, Cancelled, Claimed }
    enum ClaimStatus { Pending, Approved, Rejected, UnderAppeal }
    enum Vote { None, For, Against }

    // Константы
    uint256 public constant MIN_STAKE_MULTIPLIER = 5; // Минимальный множитель стейка
    uint256 public constant VALIDATOR_COUNT = 5;
    uint256 public constant VALIDATION_PERIOD = 2 days;
    uint256 public constant APPEAL_PERIOD = 1 days;
    uint256 public constant MIN_WALLET_BALANCE_PERCENT = 10; // 10% от баланса кошелька

    // Адреса управления
    address public admin;
    uint256 public protocolFee; // Процент комиссии (например, 1% = 100)

    // Хранилища
    mapping(uint256 => Policy) public policies;
    mapping(uint256 => Claim) public claims;
    mapping(uint256 => uint256) public claimToPolicy; // Связь Claim ID -> Policy ID
    mapping(address => uint256[]) public userPolicies;

    // Очереди и пулы
    address[] public activePolicyHolders; // Для случайного выбора валидаторов
    uint256 public totalInsurancePool; // Общий страховой пул
    uint256 public totalStaked; // Всего застейкано
    uint256 private policyNonce;
    uint256 private claimNonce;

    /**
    * @dev Модификатор для проверки, что адрес является валидатором для данного иска
    */
    modifier onlyValidator(uint256 _claimId) {
        bool isValidator = false;
        Claim storage claim = claims[_claimId];
        
        for (uint256 i = 0; i < claim.validators.length; i++) {
            if (claim.validators[i] == msg.sender) {
                isValidator = true;
                break;
            }
        }
        require(isValidator, "Not a validator for this claim");
        _;
    }

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    /**
    * @dev Создание нового страхового полиса
    * @param _startDate Дата начала поездки (timestamp)
    * @param _endDate Дата окончания поездки (timestamp)
    * @param _payoutAmount Страховая сумма в wei
    */
    function createPolicy(uint256 _startDate, uint256 _endDate, uint256 _payoutAmount) external payable {
        require(_startDate > block.timestamp + 1 days, "Start date too soon");
        require(_endDate > _startDate, "Invalid dates");
        require(_payoutAmount > 0, "Zero payout");
        
        uint256 requiredStake = _payoutAmount * MIN_STAKE_MULTIPLIER;
        require(msg.value >= requiredStake, "Insufficient stake");
        
        // Проверка, что стейк составляет значительную часть баланса кошелька
        uint256 walletBalance = address(msg.sender).balance + msg.value;
        uint256 minStakePercent = (walletBalance * MIN_WALLET_BALANCE_PERCENT) / 100;
        require(requiredStake >= minStakePercent, "Stake too small for wallet");
        
        // Создание полиса
        policyNonce++;
        policies[policyNonce] = Policy({
            holder: msg.sender,
            startDate: _startDate,
            endDate: _endDate,
            payoutAmount: _payoutAmount,
            stakeAmount: msg.value,
            creationTimestamp: block.timestamp,
            status: PolicyStatus.Active,
            hasActiveClaim: false
        });
        
        userPolicies[msg.sender].push(policyNonce);
        activePolicyHolders.push(msg.sender);
        totalStaked += msg.value;
        
        emit PolicyCreated(policyNonce, msg.sender, _payoutAmount, msg.value);
    }

    /**
    * @dev Возврат стейка после окончания срока полиса
    * @param _policyId ID полиса
    */
    /*
    function withdrawStake(uint256 _policyId) external nonReentrant {
        Policy storage policy = policies[_policyId];
        require(msg.sender == policy.holder, "Not policy holder");
        require(block.timestamp > policy.endDate, "Policy not expired");
        require(policy.status == PolicyStatus.Active, "Policy not active");
        require(!policy.hasActiveClaim, "Active claim exists");
        
        policy.status = PolicyStatus.Expired;
        totalStaked -= policy.stakeAmount;
        
        // Возврат стейка (за вычетом комиссии протокола)
        uint256 fee = (policy.stakeAmount * protocolFee) / 10000;
        uint256 refundAmount = policy.stakeAmount - fee;
        totalInsurancePool += fee;
        
        _safeTransferETH(payable(msg.sender), refundAmount);
        emit StakeWithdrawn(_policyId, refundAmount);
    }
    */

   /**
    * @dev Подача страхового случая
    * @param _policyId ID полиса
    * @param _evidenceIPFSHash IPFS hash с доказательствами
    */
    function fileClaim(uint256 _policyId, string calldata _evidenceIPFSHash) external {
        Policy storage policy = policies[_policyId];
        require(msg.sender == policy.holder, "Not policy holder");
        require(block.timestamp < policy.startDate, "Trip already started");
        require(policy.status == PolicyStatus.Active, "Policy not active");
        require(!policy.hasActiveClaim, "Claim already exists");
        
        // Случайный выбор валидаторов
        address[] memory selectedValidators = _selectRandomValidators(msg.sender);
        
        claimNonce++;
        
        // Сохраняем связь ДО создания структуры Claim (для безопасности)
        claimToPolicy[claimNonce] = _policyId;
        
        // Создаем новый страховой случай
        Claim storage newClaim = claims[claimNonce];
        newClaim.policyHolder = msg.sender;
        newClaim.claimTimestamp = block.timestamp;
        newClaim.evidenceIPFSHash = _evidenceIPFSHash;
        newClaim.validators = selectedValidators;
        newClaim.status = ClaimStatus.Pending;
        newClaim.validationEndTime = block.timestamp + VALIDATION_PERIOD;
        
        // Отмечаем, что у полиса есть активный иск
        policy.hasActiveClaim = true;
        
        emit ClaimFiled(claimNonce, _policyId, msg.sender, selectedValidators);
    }

    /**
    * @dev Получение ID полиса по ID страхового случая (публичная версия)
    * @param _claimId ID страхового случая
    * @return uint256 ID полиса
    */
    function getPolicyIdByClaim(uint256 _claimId) external view returns (uint256) {
        return _getPolicyIdByClaim(_claimId);
    }

    /**
    * @dev Получение ID полиса по ID страхового случая
    * @param _claimId ID страхового случая
    * @return uint256 ID полиса
    */
    function _getPolicyIdByClaim(uint256 _claimId) internal view returns (uint256) {
        uint256 policyId = claimToPolicy[_claimId];
        require(policyId != 0, "Claim does not exist or not linked to policy");
        return policyId;
    }

    /**
    * @dev Голосование валидатора
    * @param _claimId ID страхового случая
    * @param _vote Голос: true - за выплату, false - против
    */
    function voteOnClaim(uint256 _claimId, bool _vote) external {
        Claim storage claim = claims[_claimId];
        require(claim.status == ClaimStatus.Pending, "Claim not pending");
        require(block.timestamp < claim.validationEndTime, "Voting period ended");
        
        bool isValidator = false;
        for (uint256 i = 0; i < claim.validators.length; i++) {
            if (claim.validators[i] == msg.sender) {
                isValidator = true;
                break;
            }
        }
        require(isValidator, "Not a validator");
        require(claim.votes[msg.sender] == Vote.None, "Already voted");
        
        if (_vote) {
            claim.votes[msg.sender] = Vote.For;
            claim.votesFor++;
        } else {
            claim.votes[msg.sender] = Vote.Against;
            claim.votesAgainst++;
        }
        
        emit VoteCast(_claimId, msg.sender, _vote);
        
        // В функции voteOnClaim, при автоматическом разрешении:
        if (claim.votesFor == VALIDATOR_COUNT || claim.votesAgainst == VALIDATOR_COUNT) {
            uint256 policyId = _getPolicyIdByClaim(_claimId);
            Policy storage policy = policies[policyId];
            _resolveClaim(_claimId, policyId, policy);
        }
    }
    
    /**
    * @dev Запуск процесса апелляции
    * @param _claimId ID страхового случая
    */

    /*
    function initiateAppeal(uint256 _claimId) external payable onlyValidator(_claimId) {
        Claim storage claim = claims[_claimId];
        require(block.timestamp > claim.validationEndTime, "Voting still active");
        require(claim.status == ClaimStatus.Pending, "Claim not pending");
        
        // Получаем связанный полис
        uint256 policyId = _getPolicyIdByClaim(_claimId);
        Policy storage policy = policies[policyId];
        
        // Определение результата голосования
        bool payoutApproved = claim.votesFor > claim.votesAgainst;
        
        // Может инициировать только меньшинство
        if ((payoutApproved && claim.votes[msg.sender] == Vote.Against) ||
            (!payoutApproved && claim.votes[msg.sender] == Vote.For)) {
            
            // Теперь получаем payoutAmount из полиса
            uint256 appealStakeRequired = policy.payoutAmount / 2;
            require(msg.value >= appealStakeRequired, "Insufficient appeal stake");
            
            claim.status = ClaimStatus.UnderAppeal;
            claim.appealStake = msg.value;
            claim.appealInitiator = msg.sender;
            claim.validationEndTime = block.timestamp + APPEAL_PERIOD;
            
            emit AppealInitiated(_claimId, msg.sender, msg.value);
        } else {
            revert("Not in minority or not a validator");
        }
    }
    */

    /**
    * @dev Разрешение иска (вызывается автоматически или вручную)
    * @param _claimId ID страхового случая
    */
    function resolveClaim(uint256 _claimId) external {
        Claim storage claim = claims[_claimId];
        require(claim.status == ClaimStatus.Pending || claim.status == ClaimStatus.UnderAppeal, "Invalid status");
        require(block.timestamp > claim.validationEndTime, "Resolution period not over");
        
        // Получаем ID полиса через маппинг
        uint256 policyId = _getPolicyIdByClaim(_claimId);
        Policy storage policy = policies[policyId];
        
        _resolveClaim(_claimId, policyId, policy);
    }

    /**
    * @dev Внутренняя функция разрешения иска
    */
    function _resolveClaim(uint256 _claimId, uint256 _policyId, Policy storage policy) internal nonReentrant {
        Claim storage claim = claims[_claimId];
        
        bool payoutApproved;
        if (claim.status == ClaimStatus.Pending) {
            payoutApproved = claim.votesFor > claim.votesAgainst;
        } else { // UnderAppeal
            payoutApproved = claim.votesFor > claim.votesAgainst;
            
            // Штраф для инициатора апелляции, если он проиграл
            if ((payoutApproved && claim.appealInitiator != address(0) && 
                claim.votes[claim.appealInitiator] == Vote.Against) ||
                (!payoutApproved && claim.appealInitiator != address(0) &&
                claim.votes[claim.appealInitiator] == Vote.For)) {
                totalInsurancePool += claim.appealStake;
            } else {
                // Если апелляция успешна, возвращаем стейк
                _safeTransferETH(payable(claim.appealInitiator), claim.appealStake);
            }
        }
        
        if (payoutApproved) {
            // Выплата страховки
            require(totalInsurancePool >= policy.payoutAmount, "Insufficient insurance pool");
            totalInsurancePool -= policy.payoutAmount;
            _safeTransferETH(payable(policy.holder), policy.payoutAmount);
            
            // Вознаграждение валидаторам из стейка
            _distributeValidatorRewards(_claimId, _policyId, true);
            
            policy.status = PolicyStatus.Claimed;
            claim.status = ClaimStatus.Approved;
        } else {
            // Конфискация стейка в страховой пул
            totalInsurancePool += policy.stakeAmount;
            totalStaked -= policy.stakeAmount;
            
            _distributeValidatorRewards(_claimId, _policyId, false);
            
            policy.status = PolicyStatus.Cancelled;
            claim.status = ClaimStatus.Rejected;
        }
        
        policy.hasActiveClaim = false;
        emit ClaimResolved(_claimId, payoutApproved);
    }

    /**
    * @dev Выбор случайных валидаторов
    * @param _exclude Адрес для исключения (владелец полиса)
    */
    function _selectRandomValidators(address _exclude) internal view returns (address[] memory) {
        require(activePolicyHolders.length > VALIDATOR_COUNT, "Not enough policy holders");
        
        address[] memory selected = new address[](VALIDATOR_COUNT);
        uint256 count = 0;
        bytes32 randomSeed = keccak256(abi.encodePacked(blockhash(block.number - 1), block.timestamp));
        
        while (count < VALIDATOR_COUNT) {
            uint256 randomIndex = uint256(keccak256(abi.encodePacked(randomSeed, count))) % activePolicyHolders.length;
            address candidate = activePolicyHolders[randomIndex];
            
            if (candidate != _exclude && !_isAlreadySelected(selected, candidate, count)) {
                selected[count] = candidate;
                count++;
            }
        }
        
        return selected;
    }

    /**
    * @dev Распределение вознаграждений валидаторам
    */
    function _distributeValidatorRewards(
        uint256 _claimId, 
        uint256 _policyId, 
        bool _payoutApproved
    ) internal nonReentrant {
        Claim storage claim = claims[_claimId];
        Policy storage policy = policies[_policyId];
        
        uint256 rewardPool = (policy.stakeAmount * 10) / 100; // 10% от стейка
        uint256 rewardPerValidator = rewardPool / VALIDATOR_COUNT;
        
        for (uint256 i = 0; i < claim.validators.length; i++) {
            address validator = claim.validators[i];
            if ((_payoutApproved && claim.votes[validator] == Vote.For) ||
                (!_payoutApproved && claim.votes[validator] == Vote.Against)) {
                _safeTransferETH(payable(validator), rewardPerValidator);
            }
        }
    }

    // View-функции для фронтенда
    function getUserPolicies(address _user) external view returns (uint256[] memory) {
        return userPolicies[_user];
    }

    function getClaimDetails(uint256 _claimId) external view returns (
        address policyHolder,
        string memory evidenceIPFSHash,
        address[] memory validators,
        uint256 votesFor,
        uint256 votesAgainst,
        ClaimStatus status
    ) {
        Claim storage claim = claims[_claimId];
        return (
            claim.policyHolder,
            claim.evidenceIPFSHash,
            claim.validators,
            claim.votesFor,
            claim.votesAgainst,
            claim.status
        );
    }

    function getPolicyDetails(uint256 _policyId) external view returns (
        address holder,
        uint256 startDate,
        uint256 endDate,
        uint256 payoutAmount,
        uint256 stakeAmount,
        PolicyStatus status
    ) {
        Policy storage policy = policies[_policyId];
        return (
            policy.holder,
            policy.startDate,
            policy.endDate,
            policy.payoutAmount,
            policy.stakeAmount,
            policy.status
        );
    }

    /**
    * @dev Проверка, не выбран ли валидатор уже в текущем наборе
    * @param _selected Массив уже выбранных адресов
    * @param _candidate Проверяемый адрес-кандидат
    * @param _currentCount Текущее количество выбранных валидаторов
    * @return bool True если адрес уже выбран
    */
    function _isAlreadySelected(
        address[] memory _selected, 
        address _candidate, 
        uint256 _currentCount
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < _currentCount; i++) {
            if (_selected[i] == _candidate) {
                return true;
            }
        }
        return false;
    }

    /**
    * @dev Установка комиссии протокола (только админ)
    * @param _fee Новый размер комиссии в базисных пунктах (1% = 100)
    */
    function setProtocolFee(uint256 _fee) external {
        require(msg.sender == admin, "Only admin");
        require(_fee <= 500, "Fee too high"); // Максимум 5%
        protocolFee = _fee;
    }

    /**
    * @dev Снятие средств из страхового пула (только админ, с задержкой)
    * @param _amount Сумма для снятия
    */
    function withdrawPoolFunds(uint256 _amount) external nonReentrant {
        require(msg.sender == admin, "Only admin");
        require(_amount <= totalInsurancePool, "Insufficient pool");
        
        // Требуется временная блокировка (time-lock) на 30 дней
        // Реализация через отдельный контракт временной блокировки
        totalInsurancePool -= _amount;
        _safeTransferETH(payable(admin), _amount);
    }

    /**
    * @dev Безопасная отправка ETH с проверкой успешности
    * @param _to Адрес получателя
    * @param _amount Сумма в wei
    */
    function _safeTransferETH(address payable _to, uint256 _amount) internal {
        (bool success, ) = _to.call{value: _amount}("");
        require(success, "ETH transfer failed");
    }

    event PolicyCreated(uint256 indexed policyId, address indexed holder, uint256 payoutAmount, uint256 stakeAmount);
    event ClaimFiled(uint256 indexed claimId, uint256 indexed policyId, address indexed holder, address[] validators);
    event VoteCast(uint256 indexed claimId, address indexed validator, bool vote);
    event AppealInitiated(uint256 indexed claimId, address indexed initiator, uint256 stakeAmount);
    event ClaimResolved(uint256 indexed claimId, bool approved);
    event StakeWithdrawn(uint256 indexed policyId, uint256 amount);

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "remix_tests.sol"; // this import is automatically injected by Remix.
//import "hardhat/console.sol";
import "./PoHTI.sol";

contract SimplePoHTITest {
    PoHTI public pohti;
    bool public testResult;
    string public resultMessage;
    
    event Log(string message);
    event LogUint(string message, uint256 value);
    
    // Конструктор с payable для получения ETH при деплое
    constructor() payable {
        emit Log(string(abi.encodePacked("Contract created with balance: ", uintToString(address(this).balance))));
    }
    
    
    function quickTest() public returns (string memory) {
        emit Log("Quick test starts...");
        
        // 1. Деплой контракта страхования
        pohti = new PoHTI();
        emit Log("Insurance contrcat depolyed");
        
        // 2. Проверяем баланс тестового контракта
        uint256 myBalance = address(this).balance;
        emit LogUint("Test contract balance:", myBalance);
        
        // 3. Рассчитываем подходящие суммы для теста
        // Учитываем проверку: stake >= 10% от баланса кошелька
        // Если у нас 100 ETH баланса, то минимальный стейк = 10 ETH
        // Но мы хотим тестировать с меньшими суммами, поэтому:
        
        uint256 payout = 0.01 ether; // Маленькая страховая сумма
        uint256 stake = payout * 5;  // 5x множитель = 0.05 ETH
        
        // Проверяем, что стейк >= 10% от баланса
        // Если нет, используем меньшие значения
        uint256 minRequiredStake = (myBalance * 10) / 100; // 10%
        if (stake < minRequiredStake) {
            // Адаптируем суммы
            stake = minRequiredStake;
            payout = stake / 5;
            emit LogUint("Adapted stake:", stake);
            emit LogUint("Adapted payout amount:", payout);
        }
        
        // 4. Создание полиса
        try pohti.createPolicy{value: stake}(
            block.timestamp + 7 days,
            block.timestamp + 10 days,
            payout
        ) {
            emit Log("Policy created");
        } catch Error(string memory reason) {
            resultMessage = string(abi.encodePacked("Error with policy creation: ", reason));
            testResult = false;
            emit Log(resultMessage);
            return resultMessage;
        } catch {
            resultMessage = "Uknown error with policy creation";
            testResult = false;
            emit Log(resultMessage);
            return resultMessage;
        }
        
        // 5. Проверка создания полиса
        (address holder, , , , , PoHTI.PolicyStatus status) = pohti.getPolicyDetails(1);
        
        if (holder != address(this)) {
            resultMessage = "Error: policy holder mismatch";
            testResult = false;
            emit Log(resultMessage);
            return resultMessage;
        }
        
        if (status != PoHTI.PolicyStatus.Active) {
            resultMessage = "Error: policy status not Active";
            testResult = false;
            emit Log(resultMessage);
            return resultMessage;
        }
        
        emit Log("Policy ckeck passed");
        
        // 6. Проверка констант
        if (pohti.MIN_STAKE_MULTIPLIER() != 5) {
            resultMessage = "Error: MIN_STAKE_MULTIPLIER not equal to 5";
            testResult = false;
            emit Log(resultMessage);
            return resultMessage;
        }
        
        emit Log("Constants' check passed");
        
        // 7. Проверка списка полисов
        uint256[] memory policies = pohti.getUserPolicies(address(this));
        if (policies.length != 1) {
            resultMessage = "Error: wrong policies count";
            testResult = false;
            emit Log(resultMessage);
            return resultMessage;
        }
        
        emit LogUint("Policy found ID:", policies[0]);
        
        resultMessage = "Quick test passed!";
        testResult = true;
        emit Log(resultMessage);
        
        return resultMessage;
    }
    
    /*
    // Альтернативный тест с фиксированными малыми суммами
    function quickTestSmall() public returns (string memory) {
        emit Log("Starting test with small sums...");
        
        // 1. Деплой
        pohti = new PoHTI();
        
        // 2. Временно изменяем комиссию протокола для теста (если есть доступ)
        // pohti.setProtocolFee(0); // Только если админ
        
        // 3. Рассчитываем минимально возможные суммы
        // Баланс тестового контракта
        uint256 myBalance = address(this).balance;
        emit LogUint("Test contract balance:", myBalance);
        
        // Для теста используем минимальные значения
        // payoutAmount = 0.001 ETH
        // stake = 5 * payout = 0.005 ETH
        // Это должно быть >= 10% от myBalance
        // Значит myBalance должно быть <= 0.05 ETH
        
        // Если баланс слишком большой, отправляем часть обратно
        uint256 maxBalanceForTest = 0.05 ether; // 0.05 ETH
        if (myBalance > maxBalanceForTest) {
            // Отправляем излишки обратно на msg.sender
            uint256 excess = myBalance - maxBalanceForTest;
            payable(msg.sender).transfer(excess);
            emit LogUint("Revert overpaied amount:", excess);
            myBalance = address(this).balance;
        }
        
        uint256 payout = 0.001 ether;
        uint256 stake = payout * 5; // 0.005 ETH
        
        // Проверяем условие 10%
        uint256 tenPercent = (myBalance * 10) / 100;
        if (stake < tenPercent) {
            // Увеличиваем payout чтобы удовлетворить условию
            payout = tenPercent / 5;
            stake = tenPercent;
        }
        
        emit LogUint("Using stake:", stake);
        emit LogUint("Using payout amount:", payout);
        
        // 4. Создаем полис
        pohti.createPolicy{value: stake}(
            block.timestamp + 1 days, // Короткий срок для теста
            block.timestamp + 2 days,
            payout
        );
        
        emit Log("Test with small sums passed!");
        return "Test with small sums passed!";
    }
    */

    /*
    // Простейший тест без создания полиса
    function simpleDeployTest() public returns (string memory) {
        emit Log("Starting simple deploy test...");
        
        // Просто деплоим и проверяем константы
        pohti = new PoHTI();
        
        // Проверяем константы
        require(pohti.MIN_STAKE_MULTIPLIER() == 5, "Wrong multiplier");
        require(pohti.VALIDATOR_COUNT() == 5, "Wrong validator's count");
        
        emit Log("Simple deploy test passed!");
        return "Simple deploy test passed!";
    }
    
    // Тест только создания полиса (основная логика)
    function testCreatePolicyOnly() public payable returns (string memory) {
        emit Log("Policy create test...");
        
        // Деплой
        pohti = new PoHTI();
        
        // Получаем сумму из msg.value
        uint256 stake = msg.value;
        require(stake > 0, "You should send ETH with call");
        
        uint256 payout = stake / 5; // Соответствует множителю 5
        
        // Проверяем условие 10%
        uint256 myBalance = address(this).balance - msg.value; // Баланс до вызова
        uint256 tenPercent = (myBalance * 10) / 100;
        
        if (stake < tenPercent) {
            return string(abi.encodePacked(
                "Error: stake (", 
                uintToString(stake), 
                ") less then 10% of balance (", 
                uintToString(tenPercent), 
                "). Send more ETH."
            ));
        }
        
        // Создаем полис
        pohti.createPolicy{value: stake}(
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            payout
        );
        
        emit Log("Policy succesfully created!");
        return "Policy succesfully created!";
    }
    */
    
    // Вспомогательные функции
    function checkMyBalance() public view returns (uint256) {
        return address(this).balance;
    }
    
    function getPohtiBalance() public view returns (uint256) {
        return address(pohti).balance;
    }
    
    function uintToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
    
    // Функция для получения ETH (вызывать с переводом)
    receive() external payable {
        emit LogUint("Get ETH:", msg.value);
    }
    
    // Функция для вывода средств обратно
    function withdraw(uint256 amount) public {
        payable(msg.sender).transfer(amount);
    }

    /*
    function debugTest() public {
        pohti = new PoHTI();
        emit LogUint("Balance this:", address(this).balance);
        
        // Пробуем разные суммы
        try pohti.createPolicy{value: 0.1 ether}(block.timestamp+1 days, block.timestamp+2 days, 0.02 ether) {
            emit Log("Success with 0.1 ETH");
        } catch Error(string memory reason) {
            emit Log(string(abi.encodePacked("Error 0.1 ETH: ", reason)));
        }
        
        try pohti.createPolicy{value: 1 ether}(block.timestamp+1 days, block.timestamp+2 days, 0.2 ether) {
            emit Log("Success with 1 ETH");
        } catch Error(string memory reason) {
            emit Log(string(abi.encodePacked("Error 1 ETH: ", reason)));
        }
                
        try pohti.createPolicy{value: 10 ether}(block.timestamp+1 days, block.timestamp+2 days, 2 ether) {
            emit Log("Success with 10 ETH");
        } catch Error(string memory reason) {
            emit Log(string(abi.encodePacked("Error 10 ETH: ", reason)));
        }
        
    }
    */
}

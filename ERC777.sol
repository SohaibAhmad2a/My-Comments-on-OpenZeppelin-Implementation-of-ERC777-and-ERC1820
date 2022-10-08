//OpenZeppelin Implemention, however, I have edited it...
/* MY COMMENTS:
1. This ERC777 Token Contract implementation is backward compatible with the older ERC-20 token standard. That is why it contains all the ERC20 functionsUnlike ERC20, 
   ERC777 have the concept of default operators. A default operator is an implicitly authorized operator for all holders. ERC777 Token Contract register itself in ERC1820
   contract. Before the transfer of tokens, it also checks whether tokenholder has registered the implemention of "ERC777TokensSender" interface. Similarly, It also checks
   whether the token receiving address implemented "ERC777TokensRecipient".
2. This implementation is agnostic to the way tokens are created. This means that a supply mechanism has to be added in a derived contract using {_mint}. Support for ERC20
   is included in this contract, as specified by the EIP: both the ERC777 and ERC20 interfaces can be safely used when interacting with it. Both {IERC777-Sent} and 
   {IERC20-Transfer} events are emitted on token movements. Additionally, the {IERC777-granularity} value is hard-coded to `1`, meaning that there are no special restrictions
   in the amount of tokens that created, moved, or destroyed. This makes integration with ERC20 applications seamless.
3. ERC1820 WORKS LIKE A DIRECTORY WHERE YOU WILL ADD YOUR ERC777 CONTRACT WITH THE HELP OF FUNCTION, setInterfaceImplementer(); AND THEN SOMEONE CAN VERIFY WITH THE HELP
   OF FUNCTION, "getInterfaceImplementer(...)", THAT WHETHER YOUR CONTRACT IMPLEMENTED "ERC777TOKEN". 
4. RULES FOR OPERATOR ARE:
    - The following rules apply to any operator:
    - An address MUST always be an operator for itself. Hence an address MUST NOT ever be revoked as its own operator.
    - If an address is an operator for a holder, isOperatorFor MUST return true.
    - If an address is not an operator for a holder, isOperatorFor MUST return false.
    - The token contract MUST emit an AuthorizedOperator event with the correct values when a holder authorizes an address as its operator as defined in the AuthorizedOperator Event.
    - The token contract MUST emit a RevokedOperator event with the correct values when a holder revokes an address as its operator as defined in the RevokedOperator Event.
    - NOTE: A holder MAY authorize an already authorized operator. An AuthorizedOperator MUST be emitted each time.
    - NOTE: A holder MAY revoke an already revoked operator. A RevokedOperator MUST be emitted each time.
*/
pragma solidity ^0.8.0;

import "./IERC777.sol";
import "./IERC777Recipient.sol";
import "./IERC777Sender.sol";
import "../ERC20/IERC20.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/introspection/IERC1820Registry.sol";
contract ERC777 is Context, IERC777, IERC20 {
    using Address for address;

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    mapping(address => uint256) private _balances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    address[] private _defaultOperatorsArray;

    mapping(address => bool) private _defaultOperators;

    mapping(address => mapping(address => bool)) private _operators;
    mapping(address => mapping(address => bool)) private _revokedDefaultOperators;

    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(
        string memory name_,
        string memory symbol_,
        address[] memory defaultOperators_
    ) {
        _name = name_;
        _symbol = symbol_;

        _defaultOperatorsArray = defaultOperators_;
        for (uint256 i = 0; i < defaultOperators_.length; i++) {
            _defaultOperators[defaultOperators_[i]] = true;
        }

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));//Sets this contract to implement ERC777Token interface for itself.
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC20Token"), address(this));//Sets this contract to implement ERC20Token interface for itself.
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure virtual returns (uint8) {
        return 18;
    }

    function granularity() public view virtual override returns (uint256) {
        return 1;
    }

    function totalSupply() public view virtual override(IERC20, IERC777) returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address tokenHolder) public view virtual override(IERC20, IERC777) returns (uint256) { //Returns the amount of tokens owned by an account (`tokenHolder`)
        return _balances[tokenHolder];
    }
    /*
       Also emits a {IERC20-Transfer} event for ERC20 compatibility.
     */
    function send(
        address recipient,
        uint256 amount,
        bytes memory data
    ) public virtual override {//Send the amount of tokens from the address msg.sender to the address to. 
        _send(_msgSender(), recipient, amount, data, "", true); 
        /*This function calls two functions. One of which is "_callTokensToSend(...)", this function first checks
        whether the token holder address has registered the implemention of "ERC777TokensSender" interface, and in which contract the implementation is done?
        Then, the function of the "ERC777TokensSender" implementer is called. Almost same is the goal of other function "_callTokensReceived(...)"*/
    }
    
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
    /* Unlike `send`, `recipient` is _not_ required to implement the {IERC777Recipient} interface if it is a contract. Also emits a {Sent} event.*/
        _send(_msgSender(), recipient, amount, "", "", false);
        return true;
    }

    function burn(uint256 amount, bytes memory data) public virtual override {//Also emits a {IERC20-Transfer} event for ERC20 compatibility.
        _burn(_msgSender(), amount, data, "");
    }

    function isOperatorFor(address operator, address tokenHolder) public view virtual override returns (bool) {//Indicate whether the operator address is an operator of the tokenHolder address.
        return                                                                            
            operator == tokenHolder || //Tokenholder will be the operator for itself.
            (_defaultOperators[operator] && !_revokedDefaultOperators[tokenHolder][operator]) || //Is the operator set as default operator? and Is the operator not revoked by the holder.
            _operators[tokenHolder][operator]; //Is the opertor explicitly set as operator of the holder?
    }

    function authorizeOperator(address operator) public virtual override {//Set a third party operator address as an operator of msg.sender to send and burn tokens on its behalf.
        require(_msgSender() != operator, "ERC777: authorizing self as operator");

        if (_defaultOperators[operator]) {
            delete _revokedDefaultOperators[_msgSender()][operator];//Deleting from the "_revokedDefaultOperators" mapping
        } else {
            _operators[_msgSender()][operator] = true;
        }

        emit AuthorizedOperator(operator, _msgSender());
    }

    function revokeOperator(address operator) public virtual override {//Anyone can stop a default opertor to work on his address.
        require(operator != _msgSender(), "ERC777: revoking self as operator");//An address can't revoke itself.

        if (_defaultOperators[operator]) {
            _revokedDefaultOperators[_msgSender()][operator] = true;
        } 
        else {
            delete _operators[_msgSender()][operator];
        }

        emit RevokedOperator(operator, _msgSender());
    }
    
    function defaultOperators() public view virtual override returns (address[] memory) {//A default operator is an implicitly authorized operator for all holders. 
        return _defaultOperatorsArray;
    }

    function operatorSend(//Emits {Sent} and {IERC20-Transfer} events.
        address sender,
        address recipient,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    ) public virtual override {
        require(isOperatorFor(_msgSender(), sender), "ERC777: caller is not an operator for holder");
        _send(sender, recipient, amount, data, operatorData, true);
    }

    function operatorBurn(
        address account,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    ) public virtual override {//Emits {Burned} and {IERC20-Transfer} events.
        require(isOperatorFor(_msgSender(), account), "ERC777: caller is not an operator for holder");
        _burn(account, amount, data, operatorData);
    }

    /*
    @dev See {IERC20-allowance}. Note that operator and allowance concepts are orthogonal: operators may not have allowance, and accounts with allowance may not be
     operators themselves.
     */
    function allowance(address holder, address spender) public view virtual override returns (uint256) {
        return _allowances[holder][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     */
    function approve(address spender, uint256 value) public virtual override returns (bool) {
        address holder = _msgSender();
        _approve(holder, spender, value);
        return true;
    }
    /*
      @dev See {IERC20-transferFrom}. Emits {Sent}, {IERC20-Transfer} and {IERC20-Approval} events.
     */
    function transferFrom(
        address holder,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(holder, spender, amount);
        _send(holder, recipient, amount, "", "", false);
        return true;
    }

    /**
     * @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply. See {IERC777Sender} and {IERC777Recipient}. Emits {Minted} and {IERC20-Transfer} events.
     * Requirements:
        - `account` cannot be the zero address.
        - if `account` is a contract, it must implement the {IERC777Recipient} interface.
     */
    function _mint(
        address account,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) internal virtual {
        _mint(account, amount, userData, operatorData, true);
    }

    function _mint(
        address account,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) public virtual {
        require(account != address(0), "ERC777: mint to the zero address");

        address operator = _msgSender();

        _beforeTokenTransfer(operator, address(0), account, amount);

        // Update state variables
        _totalSupply += amount;
        _balances[account] += amount;

        _callTokensReceived(operator, address(0), account, amount, userData, operatorData, requireReceptionAck);

        emit Minted(operator, account, amount, userData, operatorData);
        emit Transfer(address(0), account, amount);
    }

    /*
     * @dev Send tokens
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
     */
    function _send(
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) internal virtual {
        require(from != address(0), "ERC777: transfer from the zero address");
        require(to != address(0), "ERC777: transfer to the zero address");

        address operator = _msgSender();

        _callTokensToSend(operator, from, to, amount, userData, operatorData);

        _move(operator, from, to, amount, userData, operatorData);

        _callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);
    }

    /**
     * @dev Burn tokens
     * @param from address token holder address
     * @param amount uint256 amount of tokens to burn
     * @param data bytes extra information provided by the token holder
     * @param operatorData bytes extra information provided by the operator (if any)
     */
    function _burn(
        address from,
        uint256 amount,
        bytes memory data,
        bytes memory operatorData
    ) internal virtual {
        require(from != address(0), "ERC777: burn from the zero address");

        address operator = _msgSender();

        _callTokensToSend(operator, from, address(0), amount, data, operatorData);

        _beforeTokenTransfer(operator, from, address(0), amount);

        // Update state variables
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC777: burn amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _totalSupply -= amount;

        emit Burned(operator, from, amount, data, operatorData);
        emit Transfer(from, address(0), amount);
    }

    function _move(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) private {
        _beforeTokenTransfer(operator, from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC777: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Sent(operator, from, to, amount, userData, operatorData);
        emit Transfer(from, to, amount);
    }

    /**
     * @dev See {ERC20-_approve}
     */
    function _approve(
        address holder,
        address spender,
        uint256 value
    ) internal virtual {
        require(holder != address(0), "ERC777: approve from the zero address");
        require(spender != address(0), "ERC777: approve to the zero address");

        _allowances[holder][spender] = value;
        emit Approval(holder, spender, value);
    }

    /**
     * @dev Call from.tokensToSend() if the interface is registered
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     */
    function _callTokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData
    ) private {
        address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(from, _TOKENS_SENDER_INTERFACE_HASH);//"getInterfaceImplementer(...)" Query if an address implements an interface and through which contract.
        if (implementer != address(0)) {
            IERC777Sender(implementer).tokensToSend(operator, from, to, amount, userData, operatorData);
        }
    }

    /**
     * @dev Call to.tokensReceived() if the interface is registered. Reverts if the recipient is a contract but
     * tokensReceived() was not registered for the recipient
     * @param operator address operator requesting the transfer
     * @param from address token holder address
     * @param to address recipient address
     * @param amount uint256 amount of tokens to transfer
     * @param userData bytes extra information provided by the token holder (if any)
     * @param operatorData bytes extra information provided by the operator (if any)
     * @param requireReceptionAck if true, contract recipients are required to implement ERC777TokensRecipient
     */
    function _callTokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) private {
        address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(to, _TOKENS_RECIPIENT_INTERFACE_HASH);
        if (implementer != address(0)) {
            IERC777Recipient(implementer).tokensReceived(operator, from, to, amount, userData, operatorData);
        } else if (requireReceptionAck) {
            require(!to.isContract(), "ERC777: token recipient contract has no implementer for ERC777TokensRecipient");
        }
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`. Does not update the allowance amount in case of infinite allowance. Revert if not enough 
     allowance is available. Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC777: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes
     * calls to {send}, {transfer}, {operatorSend}, minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

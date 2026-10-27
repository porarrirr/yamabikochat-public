/* Run npm ci --prefix ios/GenUIRuntimeTests, then node --test ios/GenUIRuntimeTests/cel.test.js. */
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const path = require('node:path');
require(path.join(__dirname, '../YamabikoChat/App/Resources/genui/cel-runtime.js'));
const GenUICEL = globalThis.GenUICEL;

function evaluate(expression, bindings) {
    return GenUICEL.evaluate({ expression, bindings });
}

test('arithmetic collections and scope read the supplied bindings', () => {
    assert.equal(evaluate('price * quantity', {price: 12, quantity: 3}).value, 36);
    assert.deepEqual(evaluate('items.map(x, x * 2)', {items: [1, 2, 3]}).value, [2, 4, 6]);
    assert.deepEqual(evaluate('items.filter(x, x >= 2)', {items: [1, 2, 3]}).value, [2, 3]);
    assert.equal(evaluate('user.name', {user: {name: 'Tokyo'}}).value, 'Tokyo');
});

test('compiled expressions read updated state', () => {
    assert.equal(evaluate('n + 1', {n: 2}).value, 3);
    assert.equal(evaluate('n + 1', {n: 8}).value, 9);
});

test('invalid expressions return the typed error without a value', () => {
    const failure = evaluate('items.map(');
    assert.equal(failure.kind, 'CELExpressionError');
    assert.ok(typeof failure.error === 'string' && failure.error.length > 0);
    assert.equal(failure.value, undefined);
    assert.equal(evaluate('1 + 1').value, 2);
});

test('mixed int and double arithmetic coerces to double', () => {
    assert.equal(evaluate('n + 1', {n: 1.5}).value, 2.5);
    assert.equal(evaluate('n + 0.5', {n: 2}).value, 2.5);
    assert.equal(evaluate('price * quantity', {price: 12.5, quantity: 3}).value, 37.5);
    assert.equal(evaluate('1.5 + 1').value, 2.5);
});

test('division is real division and zero divisors raise typed errors', () => {
    assert.equal(evaluate('7 / 2').value, 3.5);
    assert.equal(evaluate('7.0 / 2').value, 3.5);
    assert.equal(evaluate('7.5 % 2').value, 1.5);
    assert.equal(evaluate('n / 0', {n: 1}).error, 'Division by zero');
    assert.equal(evaluate('n / 0.0', {n: 1}).error, 'Division by zero');
    assert.equal(evaluate('7 % 0').error, 'Modulo by zero');
});

test('results serialize like JSON.stringify', () => {
    assert.equal(evaluate('n * n * n * n * n * n * n * n * n * n', {n: 10}).value, 10000000000);
    assert.equal(evaluate('n * n * n * n * n * n * n * n * n * n * n * n * n * n * n * n * n * n * n * n * n', {n: 10}).value, 1e21);
    assert.equal(evaluate('n * 1e308 * 10', {n: 1}).value, null);
});

test('evaluation limits reject oversized or deeply nested expressions', () => {
    assert.equal(evaluate('1 + 1'.repeat(4096)).kind, 'CELExpressionError');
    assert.equal(evaluate('('.repeat(80) + '1' + ')'.repeat(80)).kind, 'CELExpressionError');
    assert.equal(evaluate('[1,2,3]' + '.map(x, x)'.repeat(3000)).kind, 'CELExpressionError');
});

test('non-string expressions are rejected without throwing', () => {
    assert.equal(GenUICEL.evaluate({expression: 12}).kind, 'CELExpressionError');
    assert.equal(GenUICEL.evaluate({}).kind, 'CELExpressionError');
});

test('evaluateJSON wraps the same result as a JSON string', () => {
    assert.equal(GenUICEL.evaluateJSON(JSON.stringify({expression: 'price * quantity', bindings: {price: 4, quantity: 5}})), '{"value":20}');
    assert.ok(JSON.parse(GenUICEL.evaluateJSON('"broken')).kind === 'CELExpressionError');
});

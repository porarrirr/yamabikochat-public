// In-page CEL evaluation built on @marcbachmann/cel-js (MIT). See CEL-LICENSE.txt.
// Evaluation semantics: JSON bindings are plain JS numbers, mixed int/double
// arithmetic coerces to double, division is always real division,
// division/modulo by zero raise typed errors, and non-finite results serialize
// to null like JSON.stringify does.
import { Environment } from '@marcbachmann/cel-js';

const environment = new Environment({
    unlistedVariablesAreDyn: true,
    homogeneousAggregateLiterals: false,
    enableOptionalTypes: true,
    limits: { maxAstNodes: 4096, maxDepth: 64, maxListElements: 4096,
        maxMapEntries: 4096, maxCallArguments: 32 },
});

const asNumber = value => Number(value);
function divide(left, right) {
    const divisor = asNumber(right);
    if (divisor === 0) throw Error('Division by zero');
    return asNumber(left) / divisor;
}
function modulo(left, right) {
    const divisor = asNumber(right);
    if (divisor === 0) throw Error('Modulo by zero');
    return asNumber(left) % divisor;
}
// Same-type int/int and double/double division are native (the bundle patch adds
// real division and the by-zero error); only the missing mixed and double-modulo
// overloads need registering here.
for (const [left, right] of [['int', 'double'], ['double', 'int']]) {
    environment.registerOperator(`${left} / ${right}`, divide);
    environment.registerOperator(`${left} % ${right}`, modulo);
}
environment.registerOperator('double % double', modulo);
for (const [operator, apply] of [['+', (a, b) => a + b], ['-', (a, b) => a - b], ['*', (a, b) => a * b]]) {
    environment.registerOperator(`int ${operator} double`, (left, right) => apply(asNumber(left), asNumber(right)));
    environment.registerOperator(`double ${operator} int`, (left, right) => apply(asNumber(left), asNumber(right)));
}

function jsonValue(value) {
    if (typeof value === 'bigint') {
        // The previous runtime serialized every value with JSON.stringify, which
        // reduces BigInt to a double and non-finite numbers to null.
        const number = Number(value);
        return Number.isFinite(number) ? number : null;
    }
    if (Array.isArray(value)) return value.map(jsonValue);
    if (value instanceof Map) return Object.fromEntries([...value].map(([key, entry]) => [key, jsonValue(entry)]));
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, jsonValue(entry)]));
    if (typeof value === 'number' && !Number.isFinite(value)) return null;
    return value;
}

globalThis.GenUICEL = {
    evaluate(request) {
        try {
            if (typeof request.expression !== 'string') throw Error('CEL expression must be a string');
            if (request.expression.length > 4096) throw Error('CEL expression exceeds the local evaluation budget');
            return { value: jsonValue(environment.evaluate(request.expression, request.bindings || {})) };
        } catch (error) {
            return { error: String(error.message).split('\n')[0], kind: 'CELExpressionError' };
        }
    },
    evaluateJSON(request) {
        try { return JSON.stringify(this.evaluate(JSON.parse(request))); }
        catch (error) { return JSON.stringify({ error: String(error.message), kind: 'CELExpressionError' }); }
    },
};

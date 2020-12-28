const assert = require('assert');
const api = require('..');

require('./plugin.spec')

assert.equal(api.add(1, 2), 3);
console.log('ok');

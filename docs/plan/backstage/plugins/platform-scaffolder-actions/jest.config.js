/** @type {import('@jest/types').Config.InitialOptions} */
module.exports = require('@backstage/cli/config/jest')({
  rootDir: __dirname,
  coveragePathIgnorePatterns: ['node_modules', 'dist'],
});

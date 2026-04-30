
  const { Gruggle, parseChainString } = require('./gruggle');
  const gm = Gruggle.fromFiles(['graph1.g']);
  gm.chain(parseChainString('add-nodes n:1:3')).chain(['add-edges', 'lbl', 'n1', 'n3']);
  console.log(gm.toDot());

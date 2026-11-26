// Split only the outer callable parameter list. Nested callbacks, tuples and
// generic type expressions stay intact. Non-callable declarations stay inline.
export function formatSignature(signature) {
  const open=signature.indexOf('(');
  if(open<0 || /:\s*$/.test(signature.slice(0,open)))return null;
  let depth=0;
  for(let i=open;i<signature.length;i++){
    if(signature[i]==='(')depth++;
    if(signature[i]===')'&&--depth===0){
      const args=signature.slice(open+1,i).trim();
      return args?{before:signature.slice(0,open).trimEnd()+' (',args,after:signature.slice(i)}:null;
    }
  }
  return null;
}

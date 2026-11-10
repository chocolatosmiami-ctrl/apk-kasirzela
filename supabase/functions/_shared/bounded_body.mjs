export async function readBoundedText(request,limit=32768) {
  if(!request.body) throw new Error('INVALID_BODY');
  const reader=request.body.getReader(); const chunks=[]; let size=0;
  try {
    while(true) {
      const {value,done}=await reader.read(); if(done) break;
      size+=value.byteLength;
      if(size>limit) { await reader.cancel(); throw new Error('BODY_TOO_LARGE'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const data=new Uint8Array(size);let offset=0;
  for(const chunk of chunks) {data.set(chunk,offset);offset+=chunk.byteLength;}
  return new TextDecoder().decode(data);
}

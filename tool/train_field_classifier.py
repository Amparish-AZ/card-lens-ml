"""Train CardLens' compact offline business-card line classifier."""
import json, random, re
from pathlib import Path
import numpy as np
import tensorflow as tf
from faker import Faker

SEED=7319; random.seed(SEED); np.random.seed(SEED); tf.random.set_seed(SEED)
LABELS=['name','title','company','email','phone','website','address','other']
fake=Faker(['en_US','en_IN','en_GB']); Faker.seed(SEED)
titles=['Founder','Co-Founder','Chief Executive Officer','CEO','CTO','Managing Director','Director','Product Manager','Sales Manager','Software Engineer','Senior Developer','Graphic Designer','Architect','Consultant','Marketing Lead','Account Manager','Business Development Manager','Customer Relation Manager','Designated Partner','Head of Operations','Officer','Advocate','Doctor','Attorney','Professor']
company_words=['Solutions','Technologies','Tech','Labs','Studio','Enterprises','Industries','Consulting','Associates','Group','Systems','Services','Digital','Logistics','Designs','Media','Works','Innovations','Global','Ventures','Analytics','Construction','Contractors','Interiors','Accessories','Lifts','Entertainment','Property Services']
streets=['Park Road','Main Street','MG Road','Vasant Kunj Phase 1','Church Street','Market Lane','Station Road','Business Avenue','Tech Park','Industrial Estate','Lake View Road','Sector 18','Baker Street']
domains=['gmail.com','outlook.com','proton.me','yahoo.com','company.co.in','business.com','studio.design','global.io']
other_lines=['Scan me','Transforming Lives','Your Safety is Our Duty','Corporate Educational Customize Theme','Individual Homes and Apartments','Hotels Mahals Factory','School College Labs','Committed to delivering better','Construction ERP Made Easy','Best Choice For Awesome Feel','B.E. MBA LLM','Since 1998','Quality you can trust']

def noisy(s):
  if random.random()>.12:return s
  swaps={'O':'0','I':'1','l':'1','S':'5','B':'8'}
  i=random.randrange(len(s)); return s[:i]+swaps.get(s[i],s[i])+s[i+1:]
def sample(label):
  if label=='name': return noisy(fake.name())
  if label=='title': return random.choice(titles)
  if label=='company':
    base=random.choice([fake.last_name(),fake.first_name(),''.join(random.choices('ABCDEFGHIJKLMNOPQRSTUVWXYZ',k=random.randint(4,9)))])
    return base if random.random()<.28 else f'{base} {random.choice(company_words)}'+random.choice(['',' Pvt. Ltd.',' LLC',' Inc.'])
  if label=='email':
    local=re.sub(r'[^a-z0-9.]','',fake.user_name().lower());return f'{local}@{random.choice(domains)}'
  if label=='phone':
    n=''.join(random.choices('0123456789',k=10));return random.choice([f'+91 {n[:5]} {n[5:]}',f'+1 ({n[:3]}) {n[3:6]}-{n[6:]}',f'{n[:3]}-{n[3:6]}-{n[6:]}',f'M: {n}',f'{n} (WhatsApp)'])
  if label=='website':
    brand=re.sub(r'[^a-z]','',fake.last_name().lower());return random.choice([f'www.{brand}.com',f'https://{brand}.co.in',f'{brand}.io',f'www.shop.{brand}.com'])
  if label=='address':
    number=random.randint(1,999); city=random.choice(['New Delhi','Mumbai','Bengaluru','London','New York','Chennai','Pune','Hyderabad']);pin=random.choice([str(random.randint(100000,999999)),str(random.randint(10000,99999))])
    return f'{number} {random.choice(streets)}, {city} {pin}'
  return random.choice(other_lines)

def fnv(text):
  h=2166136261
  for c in text.encode('utf-8'): h=((h^c)*16777619)&0xffffffff
  return h
def features(text,index,count):
  x=np.zeros(128,np.float32); lower=text.lower().strip(); grams=list(lower)+[lower[i:i+2] for i in range(max(0,len(lower)-1))]
  for g in grams:x[fnv(g)%96]+=1
  if grams:x[:96]/=len(grams)
  letters=sum(c.isalpha() for c in text);digits=sum(c.isdigit() for c in text);upper=sum(c.isupper() for c in text);length=max(1,len(text));words=text.split()
  pats=[bool(re.search(r'\S+@\S+\.\S+',text)),bool(re.search(r'\+?\d[\d \t()./-]{6,}\d',text)),bool(re.search(r'(?:www\.|https?://|\.[a-z]{2,})',lower)),bool(re.search(r'\b(street|road|avenue|lane|suite|sector|phase|park|estate|nagar|salai|colony)\b|\b\d{5,6}\b',lower)),bool(re.search(r'\b(founder|director|manager|officer|engineer|developer|designer|consultant|ceo|cto|head|lead|partner|advocate|sales|marketing|architect|doctor)\b',lower)),bool(re.search(r'\b(inc|llc|llp|ltd|limited|corp|solutions|technologies|tech|studio|group|services|pvt|builder|construction|contractor|interior|accessories|lifts|enterprise|advocate|venture|consulting|entertainment|property)\b',lower))]
  x[96:102]=pats;x[102]=letters/length;x[103]=digits/length;x[104]=upper/max(1,letters);x[105]=min(len(words)/8,1);x[106]=min(length/100,1);x[107]=index/max(1,count-1)
  x[108]=min(text.count(',')/3,1);x[109]=min(text.count('.')/3,1);x[110]=('-' in text);x[111]=('+' in text);x[112]=(':' in text);x[113]=('&' in text);x[114]=(letters>2 and upper==letters);x[115]=sum(w[:1].isupper() for w in words)/max(1,len(words));x[116]=text[:1].isdigit();x[117]=bool(re.search(r'\b\d{5,6}\b',text));x[118]=('www.' in lower or 'http' in lower);x[119]=any(d in lower for d in domains);x[120]=pats[5];x[121]=bool(re.match(r'\d+\s+[A-Za-z]',text));x[122]=('(' in text);x[123]=sum(len(w) for w in words)/max(1,len(words)*15);x[124]=min(text.count(' ')/8,1);x[125]=('@' in text);x[126]=('/' in text);x[127]=1
  return x

def dataset(n,seed):
  random.seed(seed);X=np.zeros((n,128),np.float32);y=np.zeros(n,np.int32)
  for i in range(n):
    label=i%len(LABELS);pos={'name':0,'title':1,'company':random.choice([0,2]),'email':random.randint(3,7),'phone':random.randint(3,7),'website':random.randint(3,7),'address':random.randint(4,8),'other':random.randint(0,8)}[LABELS[label]]
    X[i]=features(sample(LABELS[label]),pos,9);y[i]=label
  order=np.random.default_rng(seed).permutation(n);return X[order],y[order]

root=Path(__file__).parents[1]
X,y=dataset(72000,SEED);Xv,yv=dataset(16000,SEED+1)

# Real lines transcribed from the 19 supplied card photographs. Each line is
# oversampled with mild OCR-like corruption so this small real corpus has useful
# influence without replacing the broad synthetic distribution.
cards=json.loads((root/'tool/real_card_training.json').read_text(encoding='utf-8'))
real=[]
for card in cards:
  count=len(card['lines'])
  for index,(text,label) in enumerate(card['lines']): real.append((text,LABELS.index(label),index,count))
Xreal=np.stack([features(text,index,count) for text,label,index,count in real]);yreal=np.array([label for text,label,index,count in real],np.int32)
aug_x=[];aug_y=[]
for repeat in range(80):
  for text,label,index,count in real:
    value=noisy(text)
    if random.random()<.18:value=value.upper()
    if random.random()<.12:value=re.sub(r'\s+',' ',value).strip()
    aug_x.append(features(value,index,count));aug_y.append(label)
X=np.concatenate([X,np.asarray(aug_x,np.float32)]);y=np.concatenate([y,np.asarray(aug_y,np.int32)])
order=np.random.default_rng(SEED+2).permutation(len(X));X=X[order];y=y[order]
model=tf.keras.Sequential([tf.keras.layers.Input((128,)),tf.keras.layers.Dense(96,activation='relu'),tf.keras.layers.Dropout(.15),tf.keras.layers.Dense(48,activation='relu'),tf.keras.layers.Dense(len(LABELS),activation='softmax')])
model.compile(optimizer=tf.keras.optimizers.Adam(2e-3),loss='sparse_categorical_crossentropy',metrics=['accuracy'])
model.fit(X,y,validation_data=(Xv,yv),epochs=10,batch_size=256,verbose=2,callbacks=[tf.keras.callbacks.EarlyStopping(patience=2,restore_best_weights=True)])
pred=np.argmax(model.predict(Xv,batch_size=512,verbose=0),axis=1);matrix=tf.math.confusion_matrix(yv,pred,num_classes=len(LABELS)).numpy();per={LABELS[i]:float(matrix[i,i]/max(1,matrix[i].sum())) for i in range(len(LABELS))}
real_pred=np.argmax(model.predict(Xreal,batch_size=256,verbose=0),axis=1)
converter=tf.lite.TFLiteConverter.from_keras_model(model);converter.optimizations=[tf.lite.Optimize.DEFAULT];tflite=converter.convert()
out=root/'assets/models/card_field_classifier.tflite';out.write_bytes(tflite)
metrics={'seed':SEED,'train_samples':len(X),'synthetic_train_samples':72000,'real_cards':len(cards),'real_labeled_lines':len(real),'real_augmented_samples':len(aug_x),'validation_samples':len(Xv),'synthetic_validation_accuracy':float((pred==yv).mean()),'real_training_accuracy':float((real_pred==yreal).mean()),'recall_by_class':per,'confusion_matrix':matrix.tolist(),'model_bytes':len(tflite),'note':'Synthetic validation and real-corpus training accuracy are not an independent real-world guarantee.'}
(root/'assets/models/training_metrics.json').write_text(json.dumps(metrics,indent=2));print(json.dumps(metrics,indent=2))

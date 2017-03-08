unit LZW;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

{function CompressStr(var bin:String):String;
function DeCompressStr(var bin:String):String;}

function CompressStream(var bin:TMemoryStream):TMemorystream;
function DecompressStream(var bin:TMemoryStream):TMemorystream; //Experemental
function GetbyteStr(src:byte):string;

implementation



//Алгоритм Лемпеля — Зива — Велча

type
  TDictPtr=^TDictEl;

  TDictEl=record
     num:word; //индексы от 0 до 65535
     data:string;
     next:TDictPtr;
  end;

  TbyteBufer=record
     data:Longword; //временное хранение байта и оставшейся части
     shift:byte; //сдвиг, или сколько уже занято бит
  end;

function GetbyteStr(src:byte):string;
var
  ct:byte;
begin
  GetbyteStr:='';
  for ct:=0 to 7 do
      if odd(src shr ct) then GetbyteStr:='1'+GetbyteStr
                         else GetbyteStr:='0'+GetbyteStr;
end;

function GetWordStr(src:longword):string;
var
  ct:byte;
begin
  GetWordStr:='';
  for ct:=0 to 31 do
      if odd(src shr ct) then GetWordStr:='1'+GetWordStr
                         else GetWordStr:='0'+GetWordStr;
end;


procedure addToDict(var Last:TDictPtr; id:byte; data:string);
var
  tmp:TDictPtr;
begin
  new(tmp);
  tmp^.data:=data;
  tmp^.num:=id;
  tmp^.next:=nil;

  if (last<>nil) then last^.next:=tmp;
  last:=tmp;
end;

function GetPtrbyData(DRoot:TDictPtr; Data:string):TDictPtr;
begin
 GetPtrbyData:=nil;
    while (GetPtrbyData=nil) and (DRoot<>nil) do
    begin
      if (Droot^.data=data) then GetPtrbyData:=Droot
                            else DRoot:=DRoot^.next;

    end;
end;

function GetPtrbyId(DRoot:TDictPtr; id:byte):TDictPtr;
begin
  GetPtrbyId:=nil;

  while (GetPtrbyId=nil) and (DRoot<>nil) do
  begin
      if (Droot^.num=id) then GetPtrbyId:=Droot
                         else DRoot:=DRoot^.next;
  end;
end;

procedure WriteData(var buf:TbyteBufer; data:word; datalen:byte);
var
  w_data:Longword;
begin
 // writeln('****Запрос на запись, данные=',GetbyteStr(data),' длинна=',datalen,'****');
 //writeln('ДО   =',GetWordStr(buf.data));
  dec(buf.shift,datalen); //коррекция сдвига
  w_data:=(data shl (buf.shift+1)); //поправка к сдвиг записи! если 1->0 2->1 3->2...
  buf.data:=buf.data or w_data;  // 1000 or 0100 = 1100
 //writeln('ПОСЛЕ=',GetWordStr(buf.data));
end;

{function ExtractByteBuf(var buf:TbyteBufer):byte;  //ВНИМАНИЕ ИЗМЕНЯЕТ БУФЕР!
begin
  writeln('******Запрос на извлечение из БУФЕРА!*******');
  {выдаем}
  ExtractByteBuf:=buf.data shr 8; //берем старший ;)
  {снимаем выданное с учета!!}
  buf.data:=buf.data shl 8;

  writeln('::='+GetByteStr(ExtractByteBuf));

  if (buf.shift<=8) then inc(buf.shift,8)
                    else  buf.shift:=15;
end; }

function ExtractData(var buf:TbyteBufer; data_len:byte):word;  //ВНИМАНИЕ ИЗМЕНЯЕТ БУФЕР! EXPEREMENTAL
begin
 // writeln('******Запрос на извлечение из БУФЕРА! длинна=',data_len,'****');
  {выдаем}
 //writeln('ДО   =',GetWordStr(buf.data));

  ExtractData:=buf.data shr (32-data_len); //берем старшие data_len бит ;)

 //writeln('Выдаю=',GetByteStr(ExtractData));

  {снимаем выданное с учета!!}
  buf.data:=buf.data shl data_len;

// writeln('ПОСЛЕ=',GetWordStr(buf.data));

  if (buf.shift+data_len<=31) then inc(buf.shift,data_len)
                              else  buf.shift:=31;
end;

function GETIndexLength(max:word):byte; //1-16
begin
   {вычислить длинну индекса}
     case max of
         0..1:        GETIndexLength:=1;
         2..3:        GETIndexLength:=2;
         4..7:        GETIndexLength:=3;
         8..15:       GETIndexLength:=4;
         16..31:      GETIndexLength:=5;
         32..63:      GETIndexLength:=6;
         64..127:     GETIndexLength:=7;
         128..255:    GETIndexLength:=8;
         256..511:    GETIndexLength:=9;
         512..1023:   GETIndexLength:=10;
         1024..2047:  GETIndexLength:=11;
         2048..4095:  GETIndexLength:=12;
         4096..8191:  GETIndexLength:=13;
         8192..16383: GETIndexLength:=14;
         16384..32767:GETIndexLength:=15;
         32768..65535:GETIndexLength:=16;
     end;
end;

function CompressStream(var bin:TMemoryStream):TMemorystream; //stable
var
  DictF,DictL,SearchRez:TDictPtr;
  bufer:TbyteBufer; //временно храним байт + остаток
  load_bufer,back_bufer:string; //сюда загрузим байты из потока

  //flags
  cur_dict_id:word;
  index_len:byte;
  found, error, full_stream:boolean;
begin

    {ini}
    CompressStream:=TmemoryStream.Create;
    error:=false;
    cur_dict_id:=0;
    bufer.data:=0;
    bufer.shift:=30;  {[31..0] 1 бит(старший) зарезервирован под хранение информ о не/четности конца цепи
                      нечетной будем считать вид: <code>|nil четной: <code>|<c byte>  => full_stream }
    full_stream:=true;


    {ini dictonary}
    DictF:=nil;
    addToDict(DictF,cur_dict_id,'');  //первый в словаре - пустой
    DictL:=DictF;

  while ((bin.Position<bin.Size) and (not error)) do
  begin
    load_bufer:='';
    found :=true;

    while ((found) and (bin.Position<bin.Size))  do  //пока такая комбинация в словаре берем еще
    begin
      load_bufer:=load_bufer+char(bin.ReadByte);
      SearchRez:=GetPtrbyData(DictF, load_bufer);
      found:=(SearchRez<>nil);
    end;

    // writeln('**load_bufer=',load_bufer);
        {цикл завершися: либо комбинация уникальна, либо иcкать болше нечего}
        if (length(load_bufer)>0) then
        begin


             {установи дилинну записи индекса
             тк пока новой записью мы пользоваться не сможем -> см по старому индексу}
             index_len:=GETIndexLength(cur_dict_id);


             {конец потока?}
             if (found) then
             begin
                //  writeln('loadbufer не уникален!');
                  {пишем индекс}
                   WriteData(bufer,SearchRez^.num,index_len); //кинем в буфер индекс
                  {сброс первых 8 бит (если надо)}
                   if (bufer.shift<24) then
                   CompressStream.WriteByte(ExtractData(bufer,8));
                  {получается цепь нечетная!! заполним 1-й первый бит на выходе}
                   full_stream:=false;
             end

        ELSE
           {запись уникальна, выполняй добавление запись и пр...}
           begin
                  {только теперь пишем словарь}
            // writeln('loadbufer уникален!');

                inc(cur_dict_id);                       //даем приращение id
                addToDict(DictL,cur_dict_id,load_bufer); //пишем в словарь
                write(cur_dict_id,', ');


                {записываем входной байт НО со сдвигом, необходимым для записи индекса}
                {вычислим предыдущую комбинацию и её байт}
                back_bufer:=copy(load_bufer,1,length(load_bufer)-1);
                SearchRez:=GetPtrbyData(DictF, back_bufer);
               // writeln('backbufer=',back_bufer);
                error:=(SearchRez=nil);

                if (not error) then
                begin
                 //   writeln('пишем индекс back=',SearchRez^.num);
                    WriteData(bufer,SearchRez^.num,index_len); //кинем в буфер индекс


                    {нужен ли сброс???}
                 if (bufer.shift<24) then     //fixed <8  not <=8) -- DERECATED now 32 bit bufer
                      CompressStream.WriteByte(ExtractData(bufer,8));


                      {запись входного БАЙТА  отрежь последний бит!}
                      load_bufer:=load_bufer[length(load_bufer)];
                   //   writeln('Запись входного байта=',load_bufer);

                       WriteData(bufer,byte(load_bufer[1]),8);
                       CompressStream.WriteByte(ExtractData(bufer,8)); //8 записал, сбрось
                 end;
            END;
        end; //конец "если буфер не пуст"
  end; //конец главный цикл

  {finalization}
  {сбросим буфер в код если там хоть что-то есть и подведем итоги}
     while (bufer.shift<31) do   //critical fix!
         CompressStream.WriteByte(ExtractData(bufer,8));


     if (not full_stream) then
        begin
           CompressStream.Position:=0;
           index_len:=(compressStream.ReadByte or 128);  //пишем 1-у в старший бит
           CompressStream.Position:=0;
           CompressStream.WriteByte(index_len);
        end;
     {убери словарь за собой:)) }
     while (DictF<>nil) do
     begin
      // writeln('deleted =',DictF^.data);
       SearchRez:=DictF;
       DictF:=DictF^.next;
       dispose(SearchRez);
     end;
     writeln('Готово: исход=',bin.Size,' сжат=',CompressStream.Size);
  {end}
end;


function DecompressStream(var bin:TMemoryStream):TMemorystream; //Experemental
var
  DictF,DictL,SearchRez:TDictPtr;
  bufer:TbyteBufer; //временно храним байт + остаток
  write_bufer:string; //сюда восстанавливаем части кода

  //flags
  index_len, need_len:byte;
  cur_dict_id:word;
  error, full_stream:boolean;
begin

    {ini}
    DecompressStream:=TmemoryStream.Create;
    error:=false;
    cur_dict_id:=0;
    bufer.data:=0;
    bufer.shift:=31; {32-битный буфер вместо 16-биного}

    {ini dictonary}
    DictF:=nil;
    addToDict(DictF,cur_dict_id,'');  //первый в словаре - пустой
    DictL:=DictF;

    {извлечем бит чет/нечет}
    if (bin.Position<bin.Size) then
       begin
        WriteData(bufer,bin.ReadByte,8);  //загрузим 1-е 8 бит
        full_stream:=(ExtractData(bufer, 1)=0);
       end;


    {готово, перейдем к циклической обработке, пока буфер НЕ пуст!}
  while ((bufer.shift<31) and (not error)) do
  begin

    write_bufer:='';

      {заполняй буфер, если нечем то EOL}
     while ((bufer.shift>6) and ((bin.Position<bin.Size))) do
     begin
       writeln('****гружу...');
       WriteData(bufer,bin.ReadByte,8);
     end;

     {вычислить длинну индекса}
     index_len:=GETIndexLength(cur_dict_id);

     {сколько нужно данных??  index_len+8bit обычто
     НО если поток не полон то +0 только в хвосте}
     need_len:=index_len;
     if (full_stream) then inc(need_len,8)
                      else
                      if (bufer.shift<24) then inc(need_len,8); //те есть 8 бит в буфере, то возьмем их, нет, так нет ;)
     writeln('нужно данных=',need_len,' бит, имеем ',31-bufer.shift);


     {***есть столько данных? да -начинаем распоковку, нет ...}
     IF  (bufer.shift<(32-need_len)) then  //== bufer.shift<=(31-need_len)
     BEGIN
         {в буфере достаточно данных, обрабатываем}
         SearchRez:=GetPtrbyId(DictF,ExtractData(bufer, index_len));
         dec(need_len,index_len);

         error:=(SearchRez=nil);

         if (NOT ERROR) then
            begin
               write_bufer:=SearchRez^.data;
               writeln('в словаре взято=',write_bufer);

                if (need_len=8) then
                   write_bufer:=write_bufer+char(ExtractData(bufer, 8));
               writeln('++ взято всего=',write_bufer);
            end;

         {от пустого буфера смысла нет}
         if (length(write_bufer)>0) then
         begin
             //а нужно ли писать в словарь??
             if (GetPtrbyData(DictF,write_bufer)=nil) then
             begin
                  inc(cur_dict_id);
                  addToDict(DictL,cur_dict_id,write_bufer); //пишем в словарь
                  writeln('Добавлено в словарь id=',cur_dict_id,' data=',write_bufer);
             end;

             DecompressStream.WriteBuffer(write_bufer[1],length(write_bufer));
         end;

     END
     else begin writeln('что-то пошло не так...'); error:=true; end;
    writeln('состояние буфера на момент конца цикла:=',GetWordStr(bufer.data));
 end; //main loop

  {убери словарь за собой:)) }
     while (DictF<>nil) do
     begin
       SearchRez:=DictF;
       DictF:=DictF^.next;
       dispose(SearchRez);
     end;

     if error then writeln('операция отменена! ошибка чтения');
 end;


end.


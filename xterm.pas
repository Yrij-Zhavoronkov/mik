unit xterm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, xterm_gui;

procedure ini_data; //инициализация деков
function mask_value(src:string):string;
procedure clean_term(system:boolean);

type
   TRead_state = (query, return, none);

var
    readln_proc_lock:TRead_state; //lock вызовом readln


implementation

const {max_lines=128; }
  max_lines=2;

type

   TGraphRec=record
       cnv:TBitmap;
       LInd_Str:Word; //индекс соотв записи в буф стрингов
   end;

   TGraphDec=record
       DEC:array [1..128] of TGraphRec; //добавляем str записиray [1..max_lines] of TGraphRec;
       First,Last:byte;
       DataLen:byte;
   end;

   //журнал
   TStrDec=record
       DEC:array of AnsiString;
       First,Last:word;
       DataLen,BufSize:word;
   end;


var
   //Lines:TStringlist;  //Буфер ввода
   //readln_proc_lock:TRead_state; //lock вызовом readln
   GraphBuf:TGraphDec;

   StringsBuf:TStrDec;


{SYS_UTILS}
function mask_value(src:string):string;
begin
   while length(src)<6 do src:=' '+src;
   mask_value:=src+' ';
end;

procedure clean_term(system:boolean);
begin
 with term do begin
  if system then
  readln_proc_lock:=none;
  lines.Clear;
  scroll_upd;
  redraw(0);
  repaint;
 end;
end;

procedure ini_data; //инициализация деков
begin
   with GraphBuf do
    begin
      DataLen:=0;
      first:=1;
      last:=1;
    end;

   with StringsBuf do
    begin
      DataLen:=0;
      BufSize:=8;
      setlength(DEC,BufSize);
      first:=0;
      last:=0;
    end;
end;

procedure  WriteStr_to_buf(src:ansistring); //добавляем str записи
var
   cur_ind:word;
begin
   with StringsBuf do
   begin
        if (DataLen+2)=BufSize then //запас в 2 ячейки
        begin
             //расширяем дек
             inc(BufSize,8);
             setlength(DEC,BufSize);
        end;

            //добавление
        cur_ind:=(last mod BufSize);
        DEC[cur_ind]:=src;
        last:=cur_ind+1;
        inc(DataLen);
   end;
end;

procedure DropStr(index:word);
var
  ch_step:byte;
begin
   //"забываем про записи" до индекса
   ch_step:=abs(StringsBuf.Last-index); //разница
   StringsBuf.Last:=index+1;
   //счетчик...
   dec(StringsBuf.DataLen,ch_step);
end;

function GetNxtIndx_inGDec(curr:byte):byte;
begin
  GetNxtIndx_inGDec:=(curr div GraphBuf.DataLen)+1;
end;

procedure GetNxtMemCel; //подг место для размещения и верни индекс
var
   ind:word;
begin
   //проверка на лимит... max_lines
   if GraphBuf.DataLen=max_lines then
      begin //удаляем последнюю запись из дека + из стриг дека

         //получить "удаляемую сроку"
         ind:=GraphBuf.Last;
         ind:=GraphBuf.DEC[ind].LInd_Str;

         //дроп
         DropStr(ind);
      end;
   //место есть.. return
   GraphBuf.Last:=GetNxtIndx_inGDec(GraphBuf.Last);
end;


{DRAW}

procedure prepare_outp_Buf(position:word;   var TOutpBuf:Tbitmap); //подготовка кадра для вывода
var
   y:word;
begin
   y:=0;
   //отрисовать туда строки с position
   while ((y<TOutpBuf.Height) and (position<>GraphBuf.Last)) do
   begin
      TOutpBuf.Canvas.Draw(2,Y,GraphBuf.DEC[position].cnv);
      position:=GetNxtIndx_inGDec(position);
   end;
end;


end.


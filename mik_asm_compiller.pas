unit mik_asm_compiller;

{$mode objfpc}{$H+}
//{$Define DEBUGMODE}

interface

uses
  Classes, SysUtils, asm_comp, main, mik_VM;


const
   max_var_len=16;
   mask_var_len=4;

   max_macros_count=128;
   max_macro_exe_level=64;
   max_macro_code_len=65535; //64кб

   max_procedures_count=128;  //max 4096

   max_mask_value=1024;   //max 4095

   MACRO_CALL_CHAR='#';
   PROC_CALL_CHAR='~';
   RETURN_VAR_MARK='*'; //эмитация передачи значения по ссылке

type
    TVarName=String[max_var_len+mask_var_len+1]; //4 - маска mFFF/pFFF
    TVarMask=String[mask_var_len];

    TBuildModes=(BM_main, BM_macros, BM_proc, fake);
    TLVarTablePTR=^TLocalVarDB;
    TLocalLnkPtr=^TLocalLnk;
    TLinkPtr=^TLink;

    {Глобальное ДБП под хранение переменных (частая операция = поиск)}
     TLink=record
     name:TVarName;
     addr:word;
     lnk_id:word;

     {для меток}
     protect:boolean;
     its_label:boolean;
     lnk2Module:byte; //1 - proc 0-main (для линкера)
     {ДБП}
     Left,Right:TLinkPtr;
           end;

TMainVarDB=object //EXPEREMENTAL

  private
       GVar_Root, //Общий
       MVar_Root, //Макросы
       PVar_Root:TLinkPtr; //Процедуры указатели на корни БДП

       DBIndex_len:word;
       DBIndex_Top:word;   //указатель на вершину стека. }

       {utils}
  procedure CreateNode(var name:TVarName; var LPTR,SelVar:TLinkPtr; var exist_var:boolean);
  procedure LineScan(var name:TVarName; var LPTR,ResultPTR:TLinkPtr);
  procedure DestroyTree(var LPTR:TLinkPtr);
  procedure AddtoIndex(LPTR:TLinkPtr);

       {info}
  public
    LVars_shift:word; //Сдвиг адrесной части (общий объем всех меток/переменных)
    DBIndex:array of TLinkPtr; //индекс переменных (компиляция/линкер)

    procedure ini;
    procedure clean;
    function TryAddVar(name:TVarName; its_label:boolean; var sel_var_id:word):byte;   //найди, нет - добавь и верни код операции
    function ReturnExistsAddr(via_name:TVarName; var addr:word):boolean;
    function ReturnExistsPTR(via_name:TVarName):TLinkPtr;
    function ExistVar(name:TVarName):boolean;
 end;

    {**************END**************}


    {mem pages (для макросов и процедур)}
     TLocalLnk=record
     name:TVarName;
     addr:word;
     last:TLocalLnkPtr;
               end;

     TLocalDBSel=(primary, temponary);

     TLocalVarDB=object
private
      top: array [0..1] of TLocalLnkPtr; {temp_db=0  1=local_db}
      {local_db:TLocalLnkPtr; сохраняемая (для макросов)
      temp_db:TLocalLnkPtr;  Расшареная / временная база (удаляется при выходе из блока)}
public
     function  empty(part:TLocalDBSel):boolean;
     procedure ini;
     procedure clear(part:TLocalDBSel);
     procedure ClearAll;
     procedure add(name:TVarName; g_addr:word; part:TLocalDBSel);
     function  search(name:TVarName; part:TLocalDBSel; var sel_var_id:word):byte;
    // function  GetPtr(name:TVarName; part:TLocalDBSel):TLocalLnkPtr;

     {$IFDEF DEBUGMODE}
     procedure print(part:TLocalDBSel);
     {$ENDIF}
end;
     {**************END**************}



 {PUBLIC PROCEDURES/FUNCTIONS}
   function  check_prm(src:string):byte;
   function  delete_comments(src:string):string;

   procedure Compile_ASM;  //experemental

   procedure ouput_log_msg(text:string; kind:byte; line:word); //0 - ok 1-warn 2-error!!
   procedure trim_spaces(mask:string; shift:byte; var src:string);
   procedure gen_code_line(src_str:String; var outp:Ansistring; var error:byte);

   procedure cut_str_value(var src,outp:string; border:char);
   function genMask(mask:word; its_procedure:boolean):TVarMask;

   function Try2RegVar(name:TVarName; its_label:boolean; var return_id:word):byte;
   function VarExists(name:TVarName):boolean;


  {$IFDEF DEBUGMODE}
  var
     {DEBUG}
     DebugCode:Textfile;
  {$ENDIF}

implementation

uses macro;

type
    TByteCodePtr=^TmemoryStream;

    {**************бд процедур**************}
    TMikProcPtr=^TMikProcInfo;

     TMikProcInfo=record
        name:TVarName;
        prm_line:string;
        return_vars:string;
        ID:word;  //порядковый номер!
        MemTablePtr:TLVarTablePTR; //указатель на табл

        last:TMikProcPtr;
     end;

   TMikProcDB=object
     private
       top:TMikProcPtr;
     public
       procedure AddNewProc(name:TVarName; prm_line:string; RetVars:string; var LMT:TLVarTablePTR; var reg_id:word);
       function  GetPtr2Procedure(name:TVarName):TMikProcPtr;
       procedure CleanMemTables;
       procedure ini;
       procedure clean_all;
    end;
   {**************END**************}

   {информация о сумматоре и переменных, имеющих то же значение  (для оптимизации вызовов)}


   TRSLinksStack=object    {структура хранит информацию о переменных отражающих содержимое сумматора}
     private                {ex   LA 4; ST AX; ST BX; ST CX;    =   AX | BX | CX;   LD rez = rez}
       data:array of word;
       pos,size:byte;
     public
       procedure ini_or_clear;
       procedure add(address:word);
       function  exist(address:word):boolean;
   end;
   {**************END**************}

   {новое: информац структ, содержащая режимы компиляции (во избежания затрат на рекурсии)}
   TBMCallPtr=^TBMCallEl;

   TBMCallEl=record
        BuildMode:TBuildModes;
        mask:TVarMask;
        MTablePTR:TLVarTablePTR; //указатель на лок-ю таблицу адресов

        last:TBMCallPtr;
   end;

   TBMCallList=object
     private
       top:TBMCallPtr;
     public
        procedure ini;
        procedure clear;
        function  ExistMode(query:TBuildModes):boolean;
        procedure push(query:TBuildModes; mask:TVarMask; LMT:TLVarTablePTR);
        procedure pop(via_mode:TBuildModes);
        procedure GetCurrentState(var BM:TBuildModes; var mask:TVarMask; var LMT:TLVarTablePTR);
        procedure GetInfo(via_mode:TBuildModes; var mask:TVarMask; var LMT:TLVarTablePTR);
   end;
   {**************END**************}


   {for CALL CODE PROC}
   TCpVarListPTR=^TCopyVarListEl;

   TCopyVarListEl=record
      FromVar,ToVar:TVarName;
      //Vtype:byte; //0 or 1    20.01.17
      last:TCpVarListPTR;
   end;


 var
  {глобальные флаги, требуются всем подчиненным функциям, управлюятся компилятором}
  {База данных переменных}
  LinksDB:TMainVarDB;
  {Стек заголовков процедур}
  MikProcDB:TMikProcDB;
  {Стек переменных.vаlue = сумматору}
  CpuRSVarList:TRSLinksStack;
  {Стек вызовов компилятора (содержит инф о режиме/маске/таблицу памяти на момент передачи упр подпрог)}
  BMCallStack:TBMCallList;

  BCContainer:TByteCodePtr;   {указатель на текущий контейнер ByteCode}


{TMainVarDB}
procedure TMainVarDB.ini; {stable}
 begin
    GVar_Root:=nil;
    MVar_Root:=nil;
    PVar_Root:=nil;

    LVars_shift:=0;
    DBIndex_len:=16;
    DBIndex_Top:=0;
    setlength(DBIndex,DBIndex_len); //[0..15]
 end;

procedure TMainVarDB.AddtoIndex(LPTR:TLinkPtr); {stable}
begin
    {расширить массив?}
    if (DBIndex_Top+5<DBIndex_len) then  //4 записи в резерве
    begin
         {add_mem_ct:=32768-DBIndex_len    //не жадничай,переполением занимается другая процедура!

         if (add_mem_ct>16) then add_mem_ct:=16; //выделяем по 16 записей (если можно)

         if not (add_mem_ct=0) then
         begin }
              inc(DBIndex_len,16);
              setlength(DBIndex,DBIndex_len);
    end;

    DBIndex[DBIndex_Top]:=LPTR;
    inc(DBIndex_Top);
end;

function  TMainVarDB.TryAddVar(name:TVarName; its_label:boolean; var sel_var_id:word):byte; {stable}
 var
    SelVar:TLinkPtr;
    need_check:boolean;
 begin
     {1 - пустая строка
      3 - несовместимость типов
      6 - переполнение стека  }
    SelVar:=nil;
    TryAddVar:=1;

    {анализ имени}
    if (length(name)>0) then
      BEGIN
         TryAddVar:=0;

         //поиск/добавление пременной/метки (сделал так а не через доп указатель т.к. корень м/б меняться)
         case name[1] of
              'm':  CreateNode(name, MVar_Root, SelVar, need_check);
              'p':  CreateNode(name, PVar_Root, SelVar, need_check);
              else  CreateNode(name, GVar_Root, SelVar, need_check);
         end;


         {проверка..}
         if (SelVar=nil) then  TryAddVar:=6
            else
            if (need_check) then
            begin
                 if not (SelVar^.its_label=its_label) then TryAddVar:=3; //несовмест типов

                 {в дальнейшем возможны доп проверки}
            end
              else {узел был создан но данные не записаны...}
            begin
                SelVar^.name:=name;
                SelVar^.lnk_id:=DBIndex_Top;  //==DBIndex_Top
                SelVar^.its_label:=its_label;
                SelVar^.protect:=false; //by default

                {информация для линкера 22.10.16}
                SelVar^.lnk2Module:=0;  //by default to main
                if (BMCallStack.ExistMode(BM_proc)) then  SelVar^.lnk2Module:=1;



                //на метки память машины не выделяется
                if (not its_label) then
                begin
                   SelVar^.addr:=LVars_shift;
                   inc(LVars_shift,2);
                end;

                {important!!!}
                AddtoIndex(SelVar);
            end;


         {return}
         if (TryAddVar=0) then
            sel_var_id:=SelVar^.lnk_id;

      END;
 end;

procedure TMainVarDB.CreateNode(var name:TVarName; var LPTR,SelVar:TLinkPtr; var exist_var:boolean); {stable}
 begin
   if (LPTR=nil) then
   BEGIN
      SelVar:=nil;
      if ((LVars_shift<main.RAM_count) and (DBIndex_Top<$FFFF)) then  //защита от переполнения (ID<FFFF и Var_Shift<RAM_count)
         begin
              new(LPTR);

              LPTR^.Left:=nil;
              LPTR^.Right:=nil;

              //return;
              SelVar:=LPTR;
              exist_var:=false;
         end;
      END
   ELSE
       if (name<LPTR^.name) then CreateNode(name,LPTR^.Left,SelVar, exist_var)
          else
       if (name>LPTR^.name) then CreateNode(name,LPTR^.Right,SelVar, exist_var)
          else
             begin  //мы нашли что искали.
                SelVar:=LPTR;
                exist_var:=true;
             end;
 end;

procedure TMainVarDB.LineScan(var name:TVarName; var LPTR,ResultPTR:TLinkPtr);
begin
 if (LPTR<>nil) then
 begin
    if (name<LPTR^.name) then LineScan(name, LPTR^.Left,ResultPTR)
                         else
    if (name>LPTR^.name) then LineScan(name, LPTR^.Right,ResultPTR)
                         else
                         ResultPTR:=LPTR;
 end;
end;

procedure TMainVarDB.DestroyTree(var LPTR:TLinkPtr);
begin
  if (LPTR<>nil) then begin
                        DestroyTree(LPTR^.Left);
                        DestroyTree(LPTR^.Right);
                        Dispose(LPTR);
                      end;
end;

procedure TMainVarDB.clean;
begin
  //очистка БД
  DestroyTree(GVar_Root);
  DestroyTree(MVar_Root);
  DestroyTree(PVar_Root);

  {setlength(DBIndex,0); }

  ini;
end;

function  TMainVarDB.ExistVar(name:TVarName):boolean;
var
    Target_tree,searchVar:TLinkPtr;
begin
  ExistVar:=false;
  {анализ имени}
    if (length(name)>0) then
      BEGIN

         case name[1] of
              'm': Target_tree:=MVar_Root;
              'p': Target_tree:=PVar_Root;
              else Target_tree:=GVar_Root;
         end;

         searchVar:=nil;
         //поиск
         LineScan(name,Target_tree,searchVar);
         ExistVar:=(searchVar <> nil);
end;
end;

function TMainVarDB.ReturnExistsAddr(via_name:TVarName; var addr:word):boolean;
var
  ResultPTR,root:TLinkPtr;
begin
  ResultPTR:=nil;
  ReturnExistsAddr:=false;

  if length(via_name)>0 then
  begin

      case via_name[1] of
              'm':  root:=MVar_Root;
              'p':  root:=PVar_Root;
              else  root:=GVar_Root;
      end;

      LineScan(via_name, root,ResultPTR);

      ReturnExistsAddr:=(ResultPTR<>nil);

      if (ReturnExistsAddr) then
         addr:=ResultPTR^.addr;
  end;
end;

function TMainVarDB.ReturnExistsPTR(via_name:TVarName):TLinkPtr; {added 20.01.17}
var
  ResultPTR,root:TLinkPtr;
begin
  ResultPTR:=nil;

  if length(via_name)>0 then
  begin

      case via_name[1] of
              'm':  root:=MVar_Root;
              'p':  root:=PVar_Root;
              else  root:=GVar_Root;
      end;

      LineScan(via_name, root,ResultPTR);

      ReturnExistsPTR:=ResultPTR;
end;
end;

{TLocalDB}

function TLocalVarDB.empty(part:TLocalDBSel):boolean;
begin
   case part of
        primary:  empty:=(top[1]=nil);
        temponary:empty:=(top[0]=nil);
   end;
end;

procedure TLocalVarDB.ini;
begin
  top[0]:=nil;
  top[1]:=nil;
end;

procedure TLocalVarDB.clear(part:TLocalDBSel);
var
    drop:TLocalLnkPtr;
    index:byte;
begin
   case part of
        primary:  index:=1;
        temponary:index:=0;
   end;

   while (top[index]<>nil) do
   begin
     drop:=top[index];
     top[index]:=top[index]^.last;
     dispose(drop);
   end;
end;

procedure TLocalVarDB.ClearAll;
begin
  clear(primary);
  clear(temponary);
end;

procedure TLocalVarDB.add(name:TVarName; g_addr:word; part:TLocalDBSel);
var
    wrk:TLocalLnkPtr;
    index:byte;
begin
   case part of
        primary:  index:=1;
        temponary:index:=0;
   end;

     new(wrk);
     wrk^.name:=name;
     wrk^.addr:=g_addr;
     wrk^.last:=top[index];
     top[index]:=wrk;
end;

function  TLocalVarDB.search(name:TVarName; part:TLocalDBSel; var sel_var_id:word):byte;
var
    wrk:TLocalLnkPtr;
    index:byte;
begin
   { 1 - пустая строка
    2 - not found
    0 - ок
    }
  search:=1;

  if length(name)>0 then
  begin
    search:=2;
    case part of
        primary:  index:=1;
        temponary:index:=0;
    end;
    wrk:=top[index];

    while ((wrk<>nil) and (search=2)) do
          begin
             if (wrk^.name=name) then
                begin
                   sel_var_id:=wrk^.addr;
                   search:=0;
                end;
              wrk:=Wrk^.last;
          end;
  end;
end;


{$IFDEF DEBUGMODE}
procedure TLocalVarDB.print(part:TLocalDBSel);
var
    base:TLocalLnkPtr;
    index:byte;
begin
   case part of
        primary:  index:=1;
        temponary:index:=0;
   end;
    base:=top[index];
    writeln(Debugcode,'Вывод содержимого таблицы========');

    while (base<>nil) do
    begin
        writeln(Debugcode,base^.name,' @',base^.addr);
        base:=base^.last;
    end;
end;
{$ENDIF}

{MMU}
function Try2RegVar(name:TVarName; its_label:boolean; var return_id:word):byte; {21.10.16 - not tested}
var
 CurBM:TBuildModes;
 CurMask:TVarMask;
 LMT:TLVarTablePTR;
 op_part:TLocalDBSel;
begin
   {функции процедуры: разграничение доступа к памяти
       - управление локальными страницами
       - управление глоб ДБ
   информацию брать из стека вызовов

    1 - пустая строка
    2 - not found
    3 - несовместимость типов
    6 - переполнение стека  }

  Try2RegVar:=1;

   if length(name)>0 then
   begin
      {запрос из стека}
      BMCallStack.GetCurrentState(CurBM,CurMask,LMT);


      {main - только прямой доступ к памяти}
      if (CurBM=BM_MAIN) then
      begin
          Try2RegVar:=LinksDB.TryAddVar(name,its_label,return_id);
          {$IFDEF DEBUGMODE}
             writeln(Debugcode,'прямой доступ ',name,' с адресом=',return_id,' код=',Try2RegVar);
          {$ENDIF}
      end
        else
        begin  {процедуры/макросы - через таблицы}

            {целевая часть таблицы временная / основная}
            op_part:=primary;
            if (its_label) then op_part:=temponary;


             {0) маловероятно но если нет табл -> создать
              1) поиск запрошеной переменной}
             if (LMT=nil) then
             begin
                new(LMT);
                LMT^.ini;
                Try2RegVar:=2; //not found
                 {$IFDEF DEBUGMODE}
                    writeln(Debugcode,'создаю таблицу!');
                 {$ENDIF}
             end
               else
               begin
                    {сначала ищем в temp, потом в pimary}
                    Try2RegVar:=LMT^.search(name, temponary, return_id);

                    if (Try2RegVar=2) then
                         Try2RegVar:=LMT^.search(name, primary, return_id);


                     {$IFDEF DEBUGMODE}
                             writeln(Debugcode,'доступ ч/з таблицу ',name,' с адресом=',return_id,' код=',Try2RegVar);
                     {$ENDIF}
               end;


                {2) добавить переменную если нет
                 a) записываем в глобальный  с маской
                 b) возвращаем АДРЕС в лок таблицу
             }
             if (Try2RegVar=2) then
             begin
                Try2RegVar:=LinksDB.TryAddVar(CurMask+name,its_label,return_id);

                if (Try2RegVar=0) then
                LMT^.add(name,return_id,op_part);

                {$IFDEF DEBUGMODE}
                   writeln(Debugcode,'записано в таблицу ',name,' с адресом=',return_id);
                {$ENDIF}
             end;
        end;
   end;
end;

function ReturnExistsAddr(via_name:TVarName; var addr:word):boolean;
var
 CurBM:TBuildModes;
 CurMask:TVarMask;
 LMT:TLVarTablePTR;
begin
   addr:=$FFFF;
   ReturnExistsAddr:=false;

   if length(via_name)>0 then
   begin
      {запрос из стека}
      BMCallStack.GetCurrentState(CurBM,CurMask,LMT);

      if (CurBM=BM_MAIN) then
      begin
          ReturnExistsAddr:=LinksDB.ReturnExistsAddr(via_name,addr);
      end
        else
        begin
          if (LMT<>nil) then  {если 1 ок то 2 провер не будет... по умолчанию операции сокращенные}
             ReturnExistsAddr:=((LMT^.search(via_name,temponary,addr)=0) or (LMT^.search(via_name,primary,addr)=0));
        end;
   end;
end;

function VarExists(name:TVarName):boolean;
var
 CurBM:TBuildModes;
 CurMask:TVarMask;
 LMT:TLVarTablePTR;
 ret_id:word;
begin
   VarExists:=false;

   if length(name)>0 then
   begin
      {запрос из стека}
      BMCallStack.GetCurrentState(CurBM,CurMask,LMT);

      if (CurBM=BM_MAIN) then
      begin
          VarExists:=LinksDB.ExistVar(name);
      end
        else
        begin
          if (LMT<>nil) then
             VarExists:=((LMT^.search(name,temponary,ret_id)=0) or (LMT^.search(name,primary,ret_id)=0));
        end;
   end;
end;

function ItLabel(name:TVarName):boolean;  {aded 20.01.17}
var
 CurBM:TBuildModes;
 CurMask:TVarMask;
 LMT:TLVarTablePTR;
 ret_id:word;
 search_label:TLinkPtr;
begin
   ItLabel:=false;

   if length(name)>0 then
   begin
      {запрос из стека}
      BMCallStack.GetCurrentState(CurBM,CurMask,LMT);

      if (CurBM=BM_MAIN) then
      begin
          search_label:=LinksDB.ReturnExistsPTR(name);
          ItLabel:=((search_label<>nil) and (search_label^.its_label));
      end

       else

        if (LMT<>nil) then
        begin
              if (LMT^.search(name,temponary,ret_id)=0)
                  then ItLabel:=LinksDB.DBIndex[ret_id]^.its_label
              else //если не нашли во временной бд

              if (LMT^.search(name,primary,ret_id)=0)
                  then ItLabel:=LinksDB.DBIndex[ret_id]^.its_label;
        end;
   end;
end;

{TBMCallStack}

procedure TBMCallList.ini;
begin
    top:=nil;
end;

procedure TBMCallList.clear;
var
   wrk:TBMCallPtr;
begin
    while (top<>nil) do
    begin
       wrk:=top;
       top:=top^.last;
       dispose(wrk);
    end;
end;

function  TBMCallList.ExistMode(query:TBuildModes):boolean;
var
   wrk:TBMCallPtr;
begin
    wrk:=top;
    ExistMode:=false;

    while (wrk<>nil) and (not ExistMode) do
    begin
       ExistMode:=(wrk^.BuildMode=query);
       wrk:=wrk^.last;
    end;
end;

procedure TBMCallList.push(query:TBuildModes; mask:TVarMask; LMT:TLVarTablePTR);
var
   wrk:TBMCallPtr;
begin
   new(wrk);
   {$IFDEF DEBUGMODE}
      writeln(debugCode,'new %', hexStr(wrk));
   {$ENDIF}

   wrk^.BuildMode:=query;
   wrk^.mask:=mask;
   wrk^.MTablePTR:=LMT;
   wrk^.last:=top;
   top:=wrk;
end;

procedure TBMCallList.pop(via_mode:TBuildModes);  {просто выносит верхний, соотв условию элемент}
var
   wrk,owner:TBMCallPtr;
begin
   wrk:=top;
   owner:=top;

   while (wrk<>nil) do
       if (wrk^.BuildMode=via_mode) then
          begin
             owner^.last:=wrk^.last; {relink}

              {$IFDEF DEBUGMODE}
                  writeln(debugCode,'dispose %',hexStr(wrk));
              {$ENDIF}

             if (wrk=top) then top:=top^.last; {protect}
             dispose(wrk);
             {stop it!!}
             break;
          end

       else
          begin
             owner:=wrk;
             wrk:=wrk^.last;
          end;
end;

procedure TBMCallList.GetCurrentState(var BM:TBuildModes; var mask:TVarMask; var LMT:TLVarTablePTR);
begin
  if (top<>nil) then
  begin
       BM:=top^.BuildMode;
       mask:=top^.mask;
       LMT:=top^.MTablePTR;
  end
    else ouput_log_msg('Критическая ошибка [Стек пуст]. Пожалуйста, сообщите о проблеме', 2, 0);
end;

procedure TBMCallList.GetInfo(via_mode:TBuildModes; var mask:TVarMask; var LMT:TLVarTablePTR);
var
   wrk:TBMCallPtr;
begin
   wrk:=top;

   while (wrk<>nil) do
   begin
     if (wrk^.BuildMode=via_mode) then
        begin
          mask:=wrk^.mask;
          LMT:=wrk^.MTablePTR;
          break;
        end;
     wrk:=wrk^.last;
   end;
end;

{TRSLinksStack}
procedure TRSLinksStack.ini_or_clear;
begin
   pos:=0;
   size:=4;
   setLength(data,size);
end;

procedure TRSLinksStack.add(address:word);
begin
    {count - кол-во  size - кол-во выделеных ячеек}
    if (pos+2=size) then
    begin
      inc(size,4);
      setLength(data,size);
    end;

  data[pos]:=address;
  inc(pos);
end;

function  TRSLinksStack.exist(address:word):boolean;
var
   index:byte;
begin
   exist:=false;

   for index:=0 to integer(pos-1) do
       if (data[index]=address) then
          begin
            exist:=true;
            break;
          end;
end;


{MASK UTILS}
function genMask(mask:word; its_procedure:boolean):TVarMask;   {STABLE}
var
  sub:byte;
  //first_chr:byte;
  first_num:byte;
begin
  genMask:='';
 // first_chr:=byte('A');
  first_num:=byte('0');

  while (mask>0) do
    begin
      sub:=mask mod 16;
      mask:=mask div 16;

      if (sub in [0..9]) then genMask:=char(first_num+sub)+genMask
                         else //genMask:=char(first_chr+sub)+genMask;  - сбоит ascii

                         case sub of
                              10:genMask:='A'+genMask;
                              11:genMask:='B'+genMask;
                              12:genMask:='C'+genMask;
                              13:genMask:='D'+genMask;
                              14:genMask:='E'+genMask;
                              15:genMask:='F'+genMask;
                         end;
    end;

  while ((length(genMask)+1)<mask_var_len) do genMask:='0'+genMask;

   if (its_procedure) then genMask:='p'+genMask
                      else genMask:='m'+genMask;
end;
{END}



{COMP CORE UTILS}
procedure cut_str_value(var src,outp:string; border:char);
var
  cp_pos:word;
begin
   cp_pos:=pos(border,src);
     if cp_pos=0 then cp_pos:=length(src)+1;

     outp:=copy(src,1,cp_pos-1);
     delete(src,1,cp_pos-1);
end;

function TryHexToInt(src:string; var ConvResult:integer):boolean;  //new 20.03.16
var
  ind:byte;
  hex_dif:Longint;
  code_zero,code_A:byte;
begin
  TryHexToInt:=true;
  delete(src,1,1);
  src:=uppercase(src);

  hex_dif:=1;
  ConvResult:=0;
  ind:=length(src);

  code_zero:=byte('0');
  code_A:=byte('A');

  if length(src)>8 then TryHexToInt:=false
                   else

                   while ((ind<0) and (TryHexToInt)) do
                   begin
                       case src[ind] of
                            '0'..'9':inc(ConvResult, hex_dif * (byte(src[ind])-code_zero));
                            'A'..'F':inc(ConvResult, hex_dif * (byte(src[ind])-code_A+10))
                            else TryHexToInt:=false;
                       end;
                       hex_dif:=hex_dif*16;
                       dec(ind);
                   end;
end;

function HexToInt(src:string):integer;  //new 20.03.16
var
  ind:byte;
  hex_dif:Longint;
  code_zero,code_A:byte;
begin
  delete(src,1,1);
  src:=uppercase(src);

  hex_dif:=1;
  HexToInt:=0;
  code_zero:=byte('0');
  code_A:=byte('A');

  for ind:=length(src) downto 1 do
  begin
   case src[ind] of
     '0'..'9':inc(HexToInt, hex_dif * (byte(src[ind])-code_zero));
     'A'..'F':inc(HexToInt, hex_dif * (byte(src[ind])-code_A+10));
   end;
     hex_dif:=hex_dif*16;
  end;
end;

procedure ouput_log_msg(text:string; kind:byte; line:word); //0 - ok 1-warn 2-error!!
var
  row:word;
begin
  row:=asm_code.SG_msg.RowCount;
  asm_code.SG_msg.RowCount:=row+1;
  asm_code.SG_msgResize(nil);
  if line=0
  then asm_code.SG_msg.Cells[0,row]:=inttostr(kind)+'  '+text
  else
  begin
     asm_code.SG_msg.Cells[0,row]:=inttostr(kind)+'  Строка: '+inttostr(line)+' '+text;
     asm_code.error_line:=line;
     asm_code.src_ed.update;
  end;
  end;

function check_prm(src:string):byte; //0-str_var 1-num 2-error 21-too long 22=nil   || up 16.10.16
var
  num:integer;
begin
check_prm:=2;

src:=UpperCase(src); //filter!
if length(src)>0 then
   begin
     CASE src[1] of
          'A'..'Z':begin  //идентификатор
                        check_prm:=0;
                        {stage 1}
                        if (length(src)>max_var_len) then check_prm:=21
                        {stage 2}                    else
                        if (pos(' ',src)+pos('@',src)+pos(',',src)+pos('$',src)>0) then check_prm:=2;
                        {stage 3}
                        //проверка на команды
                        case src of
                             'IN','OUT','HALT','ADD','SUB',
                             'CMP','LA','ST','LD','JMP','JZ','JM','PROC','ENDP':check_prm:=2;
                        end;
                     end;
              '$':if (TryHexToInt(src,num) and (num<65536)) then check_prm:=1;  //HEX WORD
         '0'..'9':if (TryStrToint(src, num)) then
                     if (num>-1) and (num<65536) then check_prm:=1;     //DEC WORD
     end;
    end
     else check_prm:=22;
end;

function delete_comments(src:string):string;
var
   end_pos:word;
begin
  end_pos:=pos('//',src);
  if end_pos>0
  then
     delete_comments:=copy(src,1,end_pos-1)
  else
     delete_comments:=src;
end;

procedure trim_spaces(mask:string; shift:byte; var src:string);
var
   sr:word;
begin
  {удалить все пробелы на участке @..<!>}
     sr:=pos(mask,src);
       while sr>0 do
       begin
            delete(src,sr+shift,1);
            sr:=pos(mask,src);
       end;
  {удалено}
end;

procedure gen_code_line(src_str:Ansistring; var outp:Ansistring; var error:byte);   // (Лексический анализ) - NEW 23.02.16
var
  i:longint;
begin
  error:=0;
  //проверить синтаксис + сгенер строку для компилятора
  {БНФ ASM MIK: [<Метка>:]<оператор> [<параметр>]
                <Метка>:=<идентификатор>
                <оператор>:=IN|OUT|HALT|LA|LD|ST|CPM|ADD|SUB|JMP|JZ|ZM|Macros|PROC
                <параметр>:=<идентефикатор>|<ЦБЗ>
                <ЦБЗ>:=<ЦБЗ>{0}{1}{2}{3}{4}{5}{6}{7}{8}{9}
                #Макрос
                ~PROCEDURE    PROC  ENDP
  }

  //этап 1 - режем комментарии -DEPRECATED
 src_str:=UPPERCASE(src_str);
 outp:='';
  //этап 2 проверка на недопуст символы + ген новой строки
  for i:=1 to length(src_str) do
      if src_str[i] in ['A'..'Z',':',';','0'..'9','_',' ',',','$',
                        MACRO_CALL_CHAR,
                        PROC_CALL_CHAR,
                        RETURN_VAR_MARK] then outp:=outp+src_str[i]
                                         else begin error:=1; break; end;

  if error=0 then
  begin
     //меняй команды на <cmd>@<параметр>;
     {1 - byte ignored!!!}
     outp:=StringReplace(outp,'ADD ','ADD@',[rfReplaceAll]);
     outp:=StringReplace(outp,'SUB ','SUB@',[rfReplaceAll]);
     outp:=StringReplace(outp,'CMP ','CMP@',[rfReplaceAll]);
     outp:=StringReplace(outp, 'LD ', 'LD@',[rfReplaceAll]);
     outp:=StringReplace(outp, 'ST ', 'ST@',[rfReplaceAll]);
     outp:=StringReplace(outp, 'LA ', 'LA@',[rfReplaceAll]);
     outp:=StringReplace(outp,'JMP ','JMP@',[rfReplaceAll]);
     outp:=StringReplace(outp, 'JZ ', 'JZ@',[rfReplaceAll]);
     outp:=StringReplace(outp, 'JM ', 'JM@',[rfReplaceAll]);

     //Крошим Все пробелы!
     trim_spaces(': ', 1, outp); trim_spaces(' :', 0, outp);
     trim_spaces('; ', 1, outp); trim_spaces(' ;', 0, outp);
     trim_spaces('@ ', 1, outp); trim_spaces(' @', 0, outp);
     //upd
     trim_spaces(', ', 1, outp); trim_spaces(' ,', 0, outp);
     trim_spaces('  ', 1, outp);  //удаление двойных, и более пробелов...
  end;
end;


procedure Proc_cmd(op_code:byte; prm:string; its_label:boolean; var err_code:byte); //только для 3 байтовых
var
  chk_code:byte;
  var_id:word;
begin
  //as label для JM JZ JMP; - обяз запись в линкер

  err_code:=0;
  chk_code:=check_prm(prm);

  if (chk_code>1) then err_code:=chk_code //2-error 21-too long 22=nil => то на выход
  else
  begin
        {*******обновление стека CpuRSVarList  (стек нужен для оптимизации CALLPROC)}
        if (op_code in [10,11,21,23]) then CpuRSVarList.ini_or_clear;

        {*******остальные с сумматором не взаимодействуют}
        case chk_code of
             0:if (Try2RegVar(prm, its_label, var_id)=0) then
               begin
                    BCContainer^.WriteByte($80+op_code); //<1>+<код>  - link
                    BCContainer^.WriteWord(var_id);

                    {обновление стека CpuRSVarList}
                    if (op_code in [21,22]) then CpuRSVarList.add(var_id);

                    {$IFDEF DEBUGMODE}
                      writeln(debugCode,'>>',op_code,' '+prm,'  $',var_id);
                      {$ENDIF}
               end;

             1:begin //константа
                     BCContainer^.WriteByte(op_code); //0=const/nil
                     if prm[1]='$' then BCContainer^.WriteWord(hextoint(prm))  //число HEX ($0 - $FFFF)
                                   else BCContainer^.WriteWord(strtoint(prm)); //число DEC (пользователь сам позаботился!)
                end;
        end;
    end;
 end;

function check_call_prm(src:string):boolean;  //25.03.16  (процедуры и ф-ии)
var
  prm:string;
begin
 check_call_prm:=true;

 if length(src)>0 then
 begin
      if (src[length(src)]=',') then check_call_prm:=false  //фикс лишней запятой в конце
      else

      //ищем все переменные разделенные запятыми
      while (check_call_prm) and (length(src)>0) do
         begin
              cut_str_value(src,prm, ',');
              delete(src,1,1);
              check_call_prm:=check_prm(trim(prm))=0; //должен быть  = 0
         end;
 end;
end;
{END}

{PROC utils}
procedure TMikProcDB.CleanMemTables;
var
  wrk:TMikProcPtr;
begin
  wrk:=top;

  while (wrk<>nil) do
  begin
      if (wrk^.MemTablePtr<>nil) then
         wrk^.MemTablePtr^.ClearAll;
         wrk:=wrk^.last;
  end;
end;

procedure TMikProcDB.AddNewProc(name:TVarName; prm_line:string; RetVars:string; var LMT:TLVarTablePTR; var reg_id:word); {UP 16.10.16}
var
  new_proc:TMikProcPtr;
begin
  new(new_proc);
  new_proc^.name:=name;
  new_proc^.prm_line:=prm_line;
  new_proc^.last:=top;
  new_proc^.return_vars:=RetVars;
  new_proc^.MemTablePtr:=LMT;

  {UP 6.10.16}
  if (top=nil) then new_proc^.ID:=0
               else new_proc^.ID:=top^.ID+1;
  top:=new_proc;

  reg_id:=new_proc^.ID;
end;

function  TMikProcDB.GetPtr2Procedure(name:TVarName):TMikProcPtr;
var
  wrk_prt:TMikProcPtr;
begin
  wrk_prt:=top;
  GetPtr2Procedure:=nil;

  while ((wrk_prt<>nil) and (GetPtr2Procedure=nil)) do
    begin
       if (wrk_prt^.name=name) then GetPtr2Procedure:=wrk_prt;
       wrk_prt:=wrk_prt^.last;
    end;
end;

procedure TMikProcDB.ini;
begin
   top:=nil;
end;

procedure TMikProcDB.clean_all;
var
  wrk_ptr:TMikProcPtr;
begin
  while (top<>nil) do
  begin
     wrk_ptr:=top;
     top:=top^.last;
     dispose(wrk_ptr);
  end;
end;


procedure GenCallCode(var query:string; CALL_ID:word; var err_code:byte; var curr_line:word); {up 20.01.17}
var
  name:TVarName;
  var_type:byte; //absolute var_lnk;
  ExistedVar:boolean;
  cp_pos,var_lnk:word;

  proc_ptr:TMikProcPtr;
  proc_prm, head_prm, cp_proc_prm, cp_head_prm:ansistring;

  proc_mask:TVarMask;
  TempMT:TLVarTablePTR;

  {update}
  CopyList,ReturnList,tempVar:TCpVarListPTR;
begin
  {копирование данных из фактических переменных во внутр.
   именно копирование, тк текущая система команд ВМ Мик иного не позволяет

   query=~PROC_NAME VAR1,VAR2,...VARN/*VarN RETURN_VAR_MARK

   коды ошибок:
   1:Ошибка вызова процедуры (процедура не найдена)
   2:Синтакисческая ошибка вызова процедуры (проверь имя процедуры)
   3:Несоответствие кол-ва формальных и фактических параметров процедуры
   92:Объявление новой процедуры в теле другой процедуры
   93:Дублирющееся имя объявляемой процедуры
   94:Синтакисческая ошибка вызова процедуры (проверь имена переменных)
   95:Обнаружена попытка вызова процедуры из тела процедуры

  }

  {$IFDEF DEBUGMODE}
     writeln(DebugCode,'****GenCallCode query=',query);
  {$ENDIF}


  delete(query,1,1);
  cp_pos:=pos(' ',query);
  if (cp_pos=0) then cp_pos:=length(query);
  name:=trim(copy(query,1,cp_pos)); //получили имя...
  delete(query,1,cp_pos);

  {$IFDEF DEBUGMODE}
     writeln(DebugCode,'   name=',name);
  {$ENDIF}

  //поиск такой процедуры
  proc_ptr:=MikProcDB.GetPtr2Procedure(name);

  if (proc_ptr=nil)
     then err_code:=1
     else
       begin
         proc_prm:=proc_ptr^.prm_line;
         head_prm:=trim(query);
         CopyList:=nil;
         ReturnList:=nil;


         proc_mask:=genMask(proc_ptr^.ID,true); ///Маска вызываемой процедуры
         TempMT:=proc_ptr^.MemTablePtr;

         {НЕ надо считывать из несуществующих переменных!   ok
          НЕ надо возвращать значения неотмеченным переменным!    ok
          {а без копирования никак для var?  --никак}
          Если в качестве переменной дали число то смотрим на него как на АДРЕС!   ok

          ЗАПРЕТИТЬ передавать метки, они не для этого!    ok
          }


          {получим список переменных для копирования}
            while ((err_code=0) and ((proc_prm>'') and (head_prm>''))) do
            begin
                cut_str_value(head_prm,cp_head_prm,',');
                cut_str_value(proc_prm,cp_proc_prm,',');

                cp_head_prm:=trim(cp_head_prm);

                delete(head_prm,1,1);
                delete(proc_prm,1,1);

                var_type:=check_prm(cp_head_prm);

                {А если прилетела константа? (здесь пользователь имеет на это право)}
                if (var_type in [0,1]) then
                begin
                  {$IFDEF DEBUGMODE}
                  writeln(DebugCode,' OPTI: var=',cp_head_prm,' объявлена=',VarExists(cp_head_prm));
                  ReturnExistsAddr(cp_head_prm,var_lnk);
                  writeln(DebugCode,' OPTI: var=',cp_head_prm,' адрес=',var_lnk);
                  writeln(DebugCode,' OPTI: var=',cp_head_prm,' содержит знач сумматора=',CpuRSVarList.exist(var_lnk));

                  {$ENDIF}


                  {переменная объявлена?   если константа -> true}
                  ExistedVar:=true;
                  if (var_type=0) then ExistedVar:=VarExists(cp_head_prm);

                  {поверка на метку! 20.01.17}

                  IF (ExistedVar) then
                     if (ItLabel(cp_head_prm)) then
                     begin  //error!!
                        ouput_log_msg(cp_head_prm+ ' - метка. Ожидается переменная или константа (адрес)',2, curr_line);
                        err_code:=94;
                     end

                  ELSE
                  BEGIN

                    {добавление в список? оптимзация --> существует переменная (импликация)  0 1 = false}
                    if ((not app_config.opimized_calls) or (ExistedVar))  //NOT TESTED
                    then
                       begin {добавляем в список на копирование}
                             new(tempVar);
                             tempVar^.last:=CopyList;
                             CopyList:=tempVar;


                             {data}
                             {если значение уже в сумматоре, то его только сохраняем}
                             if ((app_config.opimized_calls)
                                and (ReturnExistsAddr(cp_head_prm,var_lnk))
                                and (CpuRSVarList.exist(var_lnk)))
                             then
                                CopyList^.FromVar:=''
                             else
                                CopyList^.FromVar:=cp_head_prm;

                               // CopyList^.Vtype:=var_type;    20.01.17
                                CopyList^.ToVar:=cp_proc_prm;
                        end;

                        {возврат нужен? добавляем в соотв список}
                        if pos(','+cp_proc_prm+',',proc_ptr^.return_vars)>0 then
                        begin
                            new(tempVar);
                            tempVar^.last:=ReturnList;
                            tempVar^.FromVar:=cp_proc_prm;
                            tempVar^.ToVar:=cp_head_prm;
                            ReturnList:=tempVar;
                        end;
                     END; // проверка на метку 20.01.17
                   end  //  * (var_type in [0,1]) then
                 else
                     begin
                         ouput_log_msg(cp_head_prm+ ' - недопустимый идентификатор фактического параметра',2, curr_line);
                         err_code:=94;
                     end;
            end;

        if length(proc_prm+head_prm)>0 then err_code:=3;
        {ЭТАП 1 ГОТОВ!}
        {$IFDEF DEBUGMODE}
            writeln('***Этап 1 готово ',err_code);
        {$ENDIF}


        {списки готовы, копирование}
        while ((CopyList<>nil) and (err_code=0)) do
        begin
            {копир из текущей таблицы}
           { if (CopyList^.Vtype=1)
            then
            !!   //Proc_cmd(23,CopyList^.FromVar,false, err_code) //если число то LA (23)
            else }

            {фикс от 20.01.17, теперь все интерпритируется как адреса, если нужно положить число - будь добр LA сам)}
            Proc_cmd(21,CopyList^.FromVar,false, err_code); //переменная/число как адрес LD  (21)


            {*создаем фейковую запись вкл fake режим НО процедурные маску и таблицу}
            BMCallStack.push(fake,proc_mask,TempMT);

               Proc_cmd(22,CopyList^.ToVar,  false, err_code);  //ST

            {Стираем фейковую запись}
            BMCallStack.pop(fake);

          CopyList:=CopyList^.last;
        end;
         {$IFDEF DEBUGMODE}
            writeln('***Этап 1.2 готово ',err_code);
        {$ENDIF}

        {ЭТАП 2 - запиши адрес возврата...  LB=call_id
        попытка считать адрес метки "в обход" и записать в адрес возврата...eop_PROCNAME}

        {*создаем фейковую запись вкл main режим НО пустые маску и таблицу}
           BMCallStack.push(BM_MAIN,'',nil);

        if (err_code=0) then
        begin
           Proc_cmd(23,'callLB_'+inttostr(CALL_ID),TRUE, err_code); //LA  {fixed 6.10.11}
           Proc_cmd(22,'eop_'+proc_ptr^.name,      TRUE, err_code); //ST
        end;
         {$IFDEF DEBUGMODE}
            writeln('***Этап 2 готово ',err_code);
        {$ENDIF}


        {Этап 3 ВЫЗЫВАЙ ПРОЦЕДУРУ...  JMP call_PROCNAME}
        if (err_code=0) then proc_cmd(30,'call_'+proc_ptr^.name,TRUE, err_code);

         {Стираем фейковую запись}
         BMCallStack.pop(BM_MAIN);

          {$IFDEF DEBUGMODE}
            writeln('***Этап 3 готово ',err_code);
        {$ENDIF}


        {Этап 4 Пометь след оператор меткой возврата (сюда вернется управление по заверш проц)
         TryAddVar рабоает напрямую с ДБП, фейк не нужен}
        if (err_code=0) then
        begin
            err_code:=LinksDB.TryAddVar('callLB_'+inttostr(CALL_ID), true, var_lnk); {get addres fixed 6.10.11}

            if (err_code=0) then
               begin
                    LinksDB.DBIndex[var_lnk]^.addr:=BCContainer^.Size;
                    LinksDB.DBIndex[var_lnk]^.protect:=true; //запрет дальнейшего изменения!
               end;
        end;
         {$IFDEF DEBUGMODE}
            writeln('***Этап 4 готово ',err_code);
        {$ENDIF}

        {Этап 5, копируем данные из отмеченных переменных обратно}
        while ((ReturnList<>nil) and (err_code=0)) do
        begin
           {*создаем фейковую запись вкл fake режим НО процедурные маску и таблицу}
            BMCallStack.push(fake,proc_mask,TempMT);

                Proc_cmd(21,ReturnList^.FromVar,false, err_code); //LD

            {Стираем фейковую запись}
            BMCallStack.pop(fake);


            {здесь следовало ожидать проверки типа переменная/число
             НЕТ!, проверку выполняет Proc_cmd длявход параметров, и он знает что с этим делать}
                Proc_cmd(22,ReturnList^.ToVar, false, err_code); //ST

            ReturnList:=ReturnList^.last;
        end;
     end;
   {$IFDEF DEBUGMODE}
     writeln(DebugCode,'**ENDCALL CODE!');
  {$ENDIF}
END;

procedure TryRegProc(query:string;  ProcBCPointer:TByteCodePtr; var return_mask:TvarMask; var return_proc_name:TvarName; var LMT:TLVarTablePTR; var err_code:byte);   {NOT TESTED}
var
  label_id,return_id:word;
  proc_name,InclPrms,RetPrm,temp:string;
begin
   {PROC..... м/б и с ошибками
   1 - generic/syntax code error
   2 - ошибка идентификатора (имени)
   93 - процедура уже существует..
   94- Синтаксическая ошибка в ф. переменных процедуры}
  {$IFDEF DEBUGMODE}
    writeln;
  writeln('****TryRegProc query=',query);
 {$ENDIF}
   err_code:=0;
   label_id:=0;
   proc_name:='';  //incorrect name
   return_proc_name:='';
   Inclprms:='';
   RetPrm:=',';

   if (pos('PROC ',query)<>1) then err_code:=1
      else
      begin
         delete(query,1,5);
         cut_str_value(query,proc_name, ' ');
         query:=trim(query); //остались возможно параметры...
         proc_name:=trim(proc_name);
         {$IFDEF DEBUGMODE}
         writeln('name?=',proc_name);
         {$ENDIF}
      end;

   {имя в proc_name, имя коррекно? поиск по базе...}
   if (check_prm(proc_name)<>0) then err_code:=2
       else
   if (MikProcDB.GetPtr2Procedure(proc_name)<>nil) then err_code:=93;
   {$IFDEF DEBUGMODE}
         writeln('имя/дубляж ',err_code);
   {$ENDIF}




    {Разгребаем параметры...}
    while (length(query)>0) do
    begin
       cut_str_value(query,temp,',');
       delete(query,1,1);
       temp:=trim(temp);

       {$IFDEF DEBUGMODE}
         writeln('***copy ',temp);
       {$ENDIF}



       {пременная отмечена?}
       if ((length(temp)>0) and (temp[1]=RETURN_VAR_MARK)) then
       begin
          delete(temp,1,1);
          RetPrm+=(temp+',');
       end;

       if (check_prm(temp)=0) then InclPrms+=(temp+',')
                              else err_code:=94;
    end;


      {начнем регистрацию...}
      If (ERR_CODE=0)  then
      BEGIN
         {$IFDEF DEBUGMODE}
         writeln('начнем запись...');
         {$ENDIF}

         {создаем табл}
         new(LMT);
         LMT^.ini;

         MikProcDB.AddNewProc(proc_name,InclPrms,RetPrm, LMT,return_id);  //header в базу

         {зарегистрируем label, указ на начало процедуры (точка входа)}
         ERR_CODE:=LinksDB.TryAddVar('call_'+proc_name, true, label_id);

         {по идее ошибок быть не должно тк метки уникальные... но возможно переполнение}
         if (ERR_CODE=0) then
         begin
            LinksDB.DBIndex[label_id]^.addr:=ProcBCPointer^.Size; //всегда PROC
            LinksDB.DBIndex[label_id]^.protect:=true; //запрет на перезапись!
            LinksDB.DBIndex[label_id]^.lnk2Module:=1; //go to PROCEDURE
            return_proc_name:=proc_name;

            {генерируем маску}
            return_mask:=genMask(return_id,true);

         {$IFDEF DEBUGMODE}
         writeln('***ЗЕРЕГЕСТРИРОВАН code=',ERR_CODE);
         {$ENDIF}

         end;

      END;
end;

procedure ClosePROCBody(proc_name:TVarName; var err_code:byte); {not tested}
var
label_id:word;
begin
  {$IFDEF DEBUGMODE}
     writeln(debugCode,'****ClosePROCBody name=',proc_name);
  {$ENDIF}
  {зарегистрируем label, указ на адрес возврата}
   ERR_CODE:=LinksDB.TryAddVar('eop_'+proc_name, true, label_id);

         {по идее ошибок быть не должно тк метки уникальные... но возможно переполнение}
         if (ERR_CODE=0) then
         begin
            LinksDB.DBIndex[label_id]^.addr:=BCContainer^.Size+1; //(skip JMP )
            LinksDB.DBIndex[label_id]^.lnk2Module:=1;  //link to PROCERURES
            LinksDB.DBIndex[label_id]^.protect:=true; //запрет на перезапись!
         end;
   {допиши в код: JMP За пределы памяти (sigmentation error)}
    BCContainer^.WriteByte(30);
    BCContainer^.Writeword($FFFF);

   {$IFDEF DEBUGMODE}
     writeln(debugCode,'>>30 65535;');
   {$ENDIF}
end;
{END}

{COMP CORE UTILS}

procedure LinkAndWrtCode(MainModule,ProcModule:TByteCodePtr; var error_code:byte); //(линковака и запись) {NOT TESTED}
type
  TLinkFIFO=record
     Module:TByteCodePtr;
     StartBlockPos:word;
  end;

var
   StructSize:word;

   StartDataArea,StartCmdArea:word;
   Temp_data:Word;
   its_link:boolean;
   add_HALT:boolean;

   message_buf:string;

   {Очередь линковки}
   ModulesFIFO:array[0..1] of TLinkFIFO;
   ModuleId:byte;
begin
  {$IFDEF DEBUGMODE}
          writeln('*****Линковка*****');
  {$ENDIF}

      {***************************Линковка**********************************}
    ouput_log_msg('Этап 2. Линковка...',0,0);

    {SEGMENTFAIL..  если есть блок процедур, то он должен
    отделяться от основного HALT  (нули противоречат опредеению программы
    см http://it-starter.ru/content/osnovy-kompyuternoi-arkhitektury) }
    if (ProcModule^.Size>0) then
    begin

       add_HALT:=true; //если основной блок пуст - отделяем незадумываясь..

       if (MainModule^.Size>0) then
       begin
            MainModule^.Position:=MainModule^.Size-1; {индекс:=размер-1}
            add_HALT:=(MainModule^.ReadByte<>99);

            {те код завршается HALT а команда ли это? мб адрес xx99}
            if ((not add_HALT) and (MainModule^.Size>2)) then
            begin
                 { 0 1 2 3  index
                   1 2 3 4  size }
                   MainModule^.Position:=MainModule^.Size-3;
                   add_HALT:=not (MainModule^.ReadByte in [01,02,99]); //те FALSE если однобайтовая команда
            end;
      end;

      {дописываем HALT в конец, если нужно (чтобы не пустить естественный ход выполнения в блок процедур) }
       if (add_HALT) then begin
           MainModule^.Position:=MainModule^.Size;
           MainModule^.WriteByte(99);

      {$IFDEF DEBUGMODE}
         writeln('ADD HALT!!!!!!!!!!!!!');
      {$ENDIF}

       end;
    end;

    {LinksDB. DBIndex  -- проидексированные переменные, ссылайся на них}

    //всего байт =  Compiler_RAM.size;
    //память под переменные...LinksDB.LVars_count
    //2 политики... код, потом переменные / переменые, потом код...
    StructSize:=asm_code.start_val.Value+MainModule^.Size+ProcModule^.Size+LinksDB.LVars_shift;

     {$IFDEF DEBUGMODE}
         writeln('    размер записи данных: ',StructSize);
      {$ENDIF}


    {ЕСТЬ ГДЕ РАЗМЕСТИТЬ?}
    IF (StructSize>main.RAM_count)
    then begin
       ouput_log_msg('Нет места для записи '+inttostr(StructSize-asm_code.start_val.Value)+' байт кода, начиная с '+
       inttostr(asm_code.start_val.Value)+' позиции, проверь пар-ры компилятора.',2,0);
       ouput_log_msg('Этап 2. Выполение прервано из-за критической ошибки',2,0);
    end
    else
    begin
       {$IFDEF DEBUGMODE}
         writeln('    начало размещения данных...');
      {$ENDIF}

        //IF сначала переменные, потом код StartCmdBlock-начало команд / start_addr_block- адресов
        if asm_code.var_first.Checked then
           begin
              StartDataArea:=asm_code.start_val.Value;
              StartCmdArea:=StartDataArea+LinksDB.LVars_shift;

      {$IFDEF DEBUGMODE}
         writeln('    начало перемнных=',StartDataArea,' начало данных=',StartCmdArea);
      {$ENDIF}

           end
        else
           begin  //сначала код, потом переменные
              StartDataArea:=asm_code.start_val.Value+MainModule^.Size+PROCModule^.Size;
              StartCmdArea:=asm_code.start_val.Value;

      {$IFDEF DEBUGMODE}
         writeln('    начало перемнных=',StartDataArea,' начало данных=',StartCmdArea);
      {$ENDIF}

           end;


           {Составим очередь линковки
            Сначала основной модуль потом процедуры}
            ModulesFIFO[0].Module:=MainModule;
            ModulesFIFO[0].StartBlockPos:=StartCmdArea;

            ModulesFIFO[1].Module:=ProcModule;
            ModulesFIFO[1].StartBlockPos:=StartCmdArea+MainModule^.Size;

      {$IFDEF DEBUGMODE}
         writeln('    начало процедур=',ModulesFIFO[1].StartBlockPos);
      {$ENDIF}



      {Линковка *******************************}
  FOR ModuleId:=0 to 1 do
  BEGIN
    ModulesFIFO[ModuleId].Module^.Position:=0;   {IMPORTANT!!!}

    {$IFDEF DEBUGMODE}
        writeln('    сброс, начало линковки...');
      {$ENDIF}


     with ModulesFIFO[ModuleId] do
         While (Module^.Position<Module^.Size) and (error_code=0) do
         begin
             Temp_data:=Module^.ReadByte;   //command first
      {$IFDEF DEBUGMODE}
        write('        Загружена команда: ',Temp_data);
      {$ENDIF}


             //если 1-й байт=1 => ссылка
             its_link:=odd(Temp_data shr 7);

             if (its_link) then begin
                 dec(Temp_data,$80); //удаляем их кода признак ссылки

                 {$IFDEF DEBUGMODE}
                 write(' :: признак ссылки! команда=',Temp_data);
                 {$ENDIF}

             end;

           main.V_RAM.RAM[StartBlockPos+Module^.Position-1]:=Temp_data;  //command >>> to RAM

           IF not (Temp_data in [01,02,99]) then //3 байтовыe, читаем еще 2 байта
           begin
                Temp_data:=Module^.ReadWORD;
                {$IFDEF DEBUGMODE}
                  writeln('            Загрука ссылки/дек=',Temp_data,' link=',its_link);
                 {$ENDIF}


                {обр ссылки - конст пишутся без изменений}
              if its_link then
                case LinksDB.DBIndex[Temp_data]^.its_label of
             {LABEL}  TRUE:
                          if (LinksDB.DBIndex[Temp_data]^.protect)  {пользователь инициализировал метку?}
                          then
                            Temp_data:=ModulesFIFO[LinksDB.DBIndex[Temp_data]^.lnk2Module].StartBlockPos+LinksDB.DBIndex[Temp_data]^.addr //да
                          else
                          begin
                            ouput_log_msg('Метка "'+LinksDB.DBIndex[Temp_data]^.name+'" не указывает на оператор (не инициализирована)!',1,0); //нет
                            Temp_data:=0;
                            error_code:=7;
                          end;

              {VAR}   FALSE:Temp_data:=StartDataArea+LinksDB.DBIndex[Temp_data]^.addr;
                   end;

                // cout >> RAM
                main.V_RAM.RAM[StartBlockPos+Module^.Position-2]:=(Temp_data shr 8);
                main.V_RAM.RAM[StartBlockPos+Module^.Position-1]:=(Temp_data shl 8) shr 8;
           end;
        end;  //loop end
       ModulesFIFO[ModuleId].Module^.Clear;

 END; //main loop end


        {MESSAGE}
        message_buf:=inttostr(asm_code.src_ed.Lines.Count);

        if asm_code.src_ed.Lines.Count in [12,11,13,14]   //исключения 11/12/13/14 -СТРОК!!
           then Temp_data:=0
           else Temp_data:=strtoint(message_buf[length(message_buf)]); //дай последнюю цифру

        message_buf:=message_buf+' строк';

        case Temp_data of
           1:message_buf:= message_buf+'a';
           2,3,4: message_buf:= message_buf+'и';
        end;

        case error_code of
             0:ouput_log_msg('Этап 2. Компиляция проекта успешно завершена ('+message_buf+')',0,0)
             else
                 begin
                 ouput_log_msg('Этап 2. Компиляция прервана (см. лог линковки)',2,0);
                   //если активна опция очистки памяти.. чистим...
                   if asm_code.force_Clean_mem.Checked then clean_mem;
                 end;
        end;
        {END *******************************}

        {FINALIZATION}
        //авто-адрес (в насройках)
        if asm_code.set_auto_addr.Checked then main_gui.R_addr.Text:=inttostr(StartCmdArea);
    end;
end;

procedure Compile_ASM;  // (Семантический анализ + генерация промежуточного кода) experemental
var
  line_buf,code_line,prm:AnsiString;   //до 4 GB
  read_pos,L_index:word;
  {код ошибки}
  error_code:byte;

  {маскировки меток/переменых}
  TOP_MACRO_MASK:word;
  TEMP_MASK:TVarMask;
  MikRROC_NAME:TVarName;  {имя текущей процедуры (для build_mode=mik_procedure)}
  TempLMT:TLVarTablePTR;  {временная переменная для хранения указателя на таблицу перем}

  {промежуточный код
  <код> | <0|1+код><адрес> }
  MainByte_Code:TMemorystream;  //сегментация по 8/24 бита
  {модуль процедур EXPEREMENTAL}
  ProcModuleCode:TMemorystream;  //сегментация по 8/24 бита
  RunTCallID:word;  //id вызова процедуры (RunTime)

  CurrCodeLine:word; //DEBUG INFO

  {тип кода операции}
  op_code_type: (short_word,full_word,macros,s_label,mik_procedure);
begin
  {Коды ошибок:
  0 - ok
  1 - generic code error
  2 - идентификатор
  21- слишком длинный идентификатор
  3 - несовместимость типов
  4 - несоответствие кол-ва передаваемых параметров
  5 - макрос не найден
  6 - переполнение стека
  7 - nil label
  8 - Превышение лимита вывоза макросов lim=$FFFE
  9 - Объявление процедуры в теле / после тела основной программы
  91- Закрытие тела процедуры без предварительного открытия
  92- Объявление процедуры внутри другой процедуры
  93- Использование занятого имени
  94- Синтаксическая ошибка в ф. переменных процедуры
  95- вызов процедуры из тела процедуры
  101:Операция смысла не имеет (опт)    }

   {$IFDEF DEBUGMODE}
       assignFile(DebugCode,'COMPILE.DEBUG');
       rewrite(DebugCode);
       writeln(Debugcode,'Код:');
   {$ENDIF}

  //compiller ini
  read_pos:=0;
  code_line:='';
  error_code:=0;
  CurrCodeLine:=0;
  BMCallStack.ini;


  RunTCallID:=0;
  TOP_MACRO_MASK:=0;
  //SEND_MASK:='';

  {NEW}
 // build_mode:=BM_main;  //режим по-умолчанию
  BMCallStack.push(BM_main,'',nil);
  BCContainer:=@MainByte_Code;
  MikRROC_NAME:='';

  {linker}
  LinksDB.ini;
  MikProcDB.ini;
  CpuRSVarList.ini_or_clear;

  MainByte_Code:=TmemoryStream.create;
  MainByte_Code.Position:=0;

  ProcModuleCode:=TmemoryStream.create;
  ProcModuleCode.Position:=0;

  {Этап 1}
  ouput_log_msg('Компиляция начата - '+TimeToStr(Time)+' [ASM Mik compiller v 2.3a]',0,0);
  ouput_log_msg('Этап 1. Ассемблирование...',0,0);


{mein}
while (error_code=0) and (CurrCodeLine<asm_code.src_ed.Lines.Count) do
begin

   {Loopback}
   line_buf:=code_line;

         {извлечь из кода оператор / группу операторов}
   while (pos(';',line_buf)=0) and (CurrCodeLine<asm_code.src_ed.Lines.Count) do
   begin
        line_buf:=line_buf+' '+trim(delete_comments(asm_code.src_ed.Lines.Strings[CurrCodeLine]));
        inc(CurrCodeLine);
   end;
        //привести к виду по БНФ
        //результирующий код в переменной code_line
        gen_code_line(line_buf,code_line,error_code);


    if (error_code>0) then ouput_log_msg('Syntax error (Синтаксическая ошибка)',2,CurrCodeLine);

    while (length(code_line)>0) and (error_code=0) do  //обработчик
    begin
       read_pos:=pos(';',code_line);

      //Если EOL то берем,что есть ИНАЧЕ на выход...
      if read_pos=0 then
         if (CurrCodeLine=asm_code.src_ed.Lines.Count) then read_pos:=length(code_line)+1
                                                       else break;


      line_buf:=trim(copy(code_line,1,read_pos-1)); //trim command! (без ;)
      delete(code_line,1,read_pos);



       //нужный оператор получен в line_buf, обрабатываем
         while (length(line_buf)>0) and (error_code=0) do
           begin
               {EXPEREMENTAL}
                op_code_type:=short_word;

                if pos(':',line_buf)>0             then op_code_type:=s_label       else
                if pos(MACRO_CALL_CHAR,line_buf)=1 then op_code_type:=macros        else
                if pos('@',line_buf)>0             then op_code_type:=full_word     else

                if ((pos(PROC_CALL_CHAR,line_buf)=1) or (pos('PROC',line_buf)=1))   then op_code_type:=mik_procedure;
                {END INF BLOCK}

          CASE op_code_type OF
               S_LABEL: {*********************МЕТКА***********************}
                 begin


                   read_pos:=pos(':',line_buf);
                   prm:=copy(line_buf,1,read_pos-1); {имя метки}
                   delete(line_buf,1,read_pos);
                   error_code:=1;



                   if check_prm(prm)=0 then //если сюда не зайдем, то см выше... error_code:=1;
                   begin
                       {маскировка меток!!!}
                       prm:=prm;

                       error_code:=Try2RegVar(prm, true, L_Index); //get addres

                       case LinksDB.DBIndex[L_index]^.protect of
                            FALSE:begin
                                       LinksDB.DBIndex[L_index]^.addr:=BCContainer^.Size;
                                       LinksDB.DBIndex[L_index]^.protect:=true; //более не писать ничего!
                                  end;
                            TRUE: begin
                                       ouput_log_msg('Повтороное определение метки "'+prm+'"',2, CurrCodeLine);
                                       error_code:=1;
                                  end;
                      end;
                      end  else ouput_log_msg('Ожидалось <идентификатор>:TLabel, а найдено: "'+prm+'"',2, CurrCodeLine);
                  end;


               SHORT_WORD: {*****************1 БАЙТОВЫЕ ******************}
                    begin   //иначе это опер посл-ть вида <опер>

                              {$IFDEF DEBUGMODE}
                               writeln(debugCode,'>>'+line_buf);
                              {$ENDIF}

                         case line_buf of
                              'IN':  begin
                                          CpuRSVarList.ini_or_clear;
                                          BCContainer^.WriteByte(01);
                                     end;
                              'OUT': BCContainer^.WriteByte(02);
                              'HALT':BCContainer^.WriteByte(99);
                              'ENDP':
                                    if (BMCallStack.ExistMode(BM_PROC)) then
                                    begin
                                       {конец процедуры, дописываем возврат к вызову
                                       (адрес будет меняться вызовом уже в runtime)
                                       а, мы лишь позаботимся о том чтобы было известно КУДА писать адрес}
                                       //build_mode=BM_PROC
                                       ClosePROCBody(MikRROC_NAME,error_code);
                                       code_line:='$P-;'+code_line; //зеверш проц
                                    end
                                     else error_code:=91;

                              {Директивы компилятору}
                              '$M-' :
                                 begin
                                    {чистим темпы}
                                    BMCallStack.GetInfo(BM_MACROS,TEMP_MASK,TempLMT);
                                    TempLMT^.clear(temponary);

                                    {удаляем запись}
                                    BMCallStack.pop(BM_MACROS);
                                 end;
                              '$P-' :
                                 begin
                                   {чистим темпы}
                                    BMCallStack.GetInfo(BM_PROC,TEMP_MASK,TempLMT);
                                    TempLMT^.clear(temponary);

                                   {отключить режим PROC}
                                   BMCallStack.pop(BM_PROC);
                                   BCContainer:=@MainByte_Code;

                                   {загрузка предудущего режима}
                                  // BMCallStack.GetCurrentState(build_mode,SEND_MASK,TempLMT);
                                 end

                         else error_code:=1;
                         end;
                             {Обработка ошибок}
                             case error_code of
                                1 :ouput_log_msg('"'+line_buf+'" - Неверная команда или синтаксическая ошибка',2,CurrCodeLine);
                                91:ouput_log_msg('Встречен "'+line_buf+'", однако не найден предшествующий PROC ',2,CurrCodeLine);
                             end;
                             line_buf:='';
                     end;


               FULL_WORD:
                   begin {*****************3 БАЙТОВЫЕ + ПРОЦЕДУРЫ**************}
                       read_pos:=pos('@',line_buf);
                       prm:=copy(line_buf,read_pos+1,length(line_buf));
                       line_buf:=copy(line_buf,1,read_pos-1);

                          case line_buf of
                              'ADD':Proc_cmd(10,prm,false, error_code);
                              'SUB':Proc_cmd(11,prm,false, error_code);
                              'CMP':Proc_cmd(12,prm,false, error_code);
                              'LD' :Proc_cmd(21,prm,false, error_code);
                              'ST' :Proc_cmd(22,prm,false, error_code);
                              'LA' :begin
                                      {$IFDEF DEBUGMODE}
                                              writeln(debugCode,'>> 23 '+prm,';');
                                      {$ENDIF}

                                      BCContainer^.WriteByte(23);  //const
                                      if check_prm(prm)=1 then
                                         BCContainer^.WriteWord(strtoint(prm))
                                      else
                                       begin
                                       ouput_log_msg('LA: ожидалось [0..65535],но найдено: "'+prm+'" ',2,CurrCodeLine);
                                       error_code:=1;  //FIX 27.02.16; = stream read error
                                       end;
                                    end;
                              'JMP':proc_cmd(30,prm,TRUE, error_code);
                              'JZ' :proc_cmd(33,prm,TRUE, error_code);
                              'JM' :proc_cmd(34,prm,TRUE, error_code);
                          end;
                               case error_code of    //++fix 23.04.16
                                  1  :ouput_log_msg('Неверная конструкция/команда или синтаксическая ошибка',2,CurrCodeLine);
                                  2  :ouput_log_msg('Неверный идентификатор (см. правила постороения имен)', 2, CurrCodeLine);
                                  3  :ouput_log_msg('Несоместиммые типы: Метка и переменная', 2, CurrCodeLine);
                                  21 :ouput_log_msg('Слишком длинный идентификатор (макс. длинна = '+inttostr(max_var_len)+')', 2, CurrCodeLine);
                                  22 :ouput_log_msg('Для команды: '+line_buf+' отсутствует идентификатор/константа', 2, CurrCodeLine);
                                  101:begin
                                        ouput_log_msg('Команда: '+line_buf+' не имеет смысла и была пропущена', 1, CurrCodeLine);
                                        {тк это не крит ошибка, а предупреждение то выполнение надо продолжить}
                                        error_code:=0;
                                      end;
                               end;
                               line_buf:='';
                     end;

               MACROS:
                      begin
                        {**************************MACRO*****************************}
                          if (TOP_MACRO_MASK<max_mask_value) then  //введем ограничение на кол-во вызовов макросов
                          begin
                             TempLMT:=nil;
                             prm:=proc_macro_code(line_buf, TempLMT ,error_code);  {Получи код (тело) макроса}

                              {$IFDEF DEBUGMODE}
                               writeln(debugCode,'код макrоса: ',prm,' адрес таблицы=',hexstr(TempLMT));
                              {$ENDIF}
                            {положим информ-ю в стек}
                               if (error_code=0) then
                               begin
                                    {ген маску}
                                    inc(TOP_MACRO_MASK);
                                    BMCallStack.push(BM_macros, genMask(TOP_MACRO_MASK, false), TempLMT);

                                    {Закрываем директивой код макросов +встраив код макроса в основной код..}
                                    code_line:=prm+'$M-;'+code_line;
                               end;
                           end
                             else error_code:=8;


                            {ВЫВОД СООБЩЕНИЯ ПОЛЬЗОВАТЕЛЮ}
                                   delete(line_buf,1,1);
                                   cut_str_value(line_buf,prm, ' '); //получи имя...

                                   while pos('  ',line_buf)>0 do   //удали лишние пробелы в параметрах...
                                         line_buf:=StringReplace(line_buf,'  ',' ',[rfReplaceAll]);
                                         line_buf:=UPPERCASE(prm+' ('+trim(line_buf)+').');


                                       ouput_log_msg('Компиляция, цель: макрос '+line_buf, 1, 0);
                            {КОН ВЫВОД СООБЩЕНИЯ ПОЛЬЗОВАТЕЛЮ}

                           //обработака ошибок
                           case error_code of
                                4:ouput_log_msg('Несоответствие кол-ва формальных и фактических параметров', 2, CurrCodeLine);
                                5:ouput_log_msg('Вызов несуществующего/незарегистрированного макроса? ', 2, CurrCodeLine);
                                8:ouput_log_msg('Превышен общий лимит вызова макросов (='+inttostr(max_mask_value)+')', 2, CurrCodeLine);
                            end;
                        line_buf:='';
                        prm:='';
                      end;
               MIK_PROCEDURE:
                      begin
                         {начало процедуры = block.size и доступен как call_PROCNAME; - метка
                         конец процедуры доступен как endp_PROCNAME со сдвигом в 1 байт (для записи адреса возврата) - метка as переменная}

                         {ВЫЗОВ копирование данных их фактических в формальные и наоборот..}
                       IF (error_code=0) then
                         if (line_buf[1]=PROC_CALL_CHAR)
                            then
                                begin
                                   GenCallCode(line_buf, RunTCallID, error_code, CurrCodeLine); {fixed}
                                   inc(RunTCallID);
                                end
                            else
                                begin  //PROC <name> <prms>
                                    {добавили в список, дали точку входа call_MikRROC_NAME}
                                    TryRegProc(line_buf, @ProcModuleCode, TEMP_MASK, MikRROC_NAME, TempLMT, error_code);  {ACHTUNG SET MASK to line_buf}

                                    if (error_code=0) then
                                    begin
                                       {'$P+' : {PROCEDURE mask mode}}

                                       {если режим уже активен = ошика т.к. конструкции
                                           procedure ..
                                             procedure ....  end;
                                              end; запрещены во всех языках!}

                                         if BMCallStack.ExistMode(BM_proc)
                                            then error_code:=92
                                         else
                                            begin

                                               {маску нам должен был дать обработчик PROC}
                                               BMCallStack.push(BM_proc, TEMP_MASK, TempLMT);
                                               BCContainer:=@ProcModuleCode;
                                            end;
                                    end;
                                end;

                         //---------обработка/вывод ошибок-----------------------
                         case error_code of
                              1:ouput_log_msg('Ошибка вызова процедуры (процедура не найдена)',2,CurrCodeLine);
                              2:ouput_log_msg('Синтакисческая ошибка вызова процедуры (проверь имя процедуры)',2,CurrCodeLine);
                              3:ouput_log_msg('Несоответствие кол-ва формальных и фактических параметров процедуры', 2, CurrCodeLine);
                              92:ouput_log_msg('Объявление новой процедуры в теле другой процедуры',2,CurrCodeLine);
                              93:ouput_log_msg('Дублирющееся имя объявляемой процедуры',2,CurrCodeLine);
                              94:ouput_log_msg('Синтакисческая ошибка вызова процедуры (проверь имена переменных)',2,CurrCodeLine);
                              95:ouput_log_msg('Обнаружена попытка вызова процедуры из тела процедуры',2,CurrCodeLine);
                         end;


                         line_buf:='';
                      end;


             END; //end of global case
          end; //main code analyzer loop end;
         end; //main loop

end; //mein while end
{$IFDEF DEBUGMODE}
    writeln('****** вызов линковщика ********');
{$ENDIF}

  {***************************Линковка*****************************************}
 if error_code>0 then ouput_log_msg('Этап 1. Компиляция завершилась неудачей. (см. лог компиляции)',2,0)
                 else
     LinkAndWrtCode(@MainByte_Code,@ProcModuleCode,error_code); //линкуем и пишем в V RAM

 {FINALIZATION}
  if (error_code=0) and (asm_code.hide_after.Checked) then  asm_code.Close;

 {CLEAN UP}
  LinksDB.clean;
  MikProcDB.clean_all;
  CpuRSVarList.ini_or_clear;


  {очистка таблиц}
     macros_list.CleanMemTables;
     MikProcDB.CleanMemTables;


  {$IFDEF DEBUGMODE}
       closeFile(DebugCode);
   {$ENDIF}


  //gedraw GUI
  main_gui.mem_gui.Repaint;
end;

{END COMPILER CODE SECTION}

{SID}
procedure create_BashScript(fname:string);
BEGIN
   {
        unsigned char   e_ident[EI_NIDENT];     /* Сигнатура и прочая информаци
я */
        Elf32_Half      e_type;                 /* Тип объектного файла */
        Elf32_Half      e_machine;              /* Аппаратная платформа (архите
ктура) */
        Elf32_Word      e_version;              /* Номер версии */
        Elf32_Addr      e_entry;                /* Адрес точки входа (стартовый
 адрес программы) */
        Elf32_Off       e_phoff;                /* Смещение от начала файла таб
лицы программных заголовков */
        Elf32_Off       e_shoff;                /* Смещение от начала файла таб
лицы заголовков секций */
        Elf32_Word      e_flags;                /* Специфичные флаги процессора
 (не используется в архитектуре i386) */
        Elf32_Half      e_ehsize;               /* Размер ELF-заголовка в байта
х */
        Elf32_Half      e_phentsize;            /* Размер записи в таблице прог
раммных заголовков */
        Elf32_Half      e_phnum;                /* Количество записей в таблице
 программных заголовков */
        Elf32_Half      e_shentsize;            /* Размер записи в таблице заго
ловков секций */
        Elf32_Half      e_shnum;                /* Количество записей в таблице
 заголовков секций */
        Elf32_Half      e_shstrndx;             /* Расположение сегмента, содер
жащего таблицy стpок */
 Elf32_Ehdr;

  7F
   45
   4C
   46
   1 = 32bit / 2=64
   1 - байты следуют в порядке младший-старший (intel) 2-наоборот;
   1 - номер версии заголовка
   0 – UNIX System V ABI;
   0 - хз
   0 - 9-й байт = начало зарезервированных байтов по 16-й!!
   2  ET_EXEC – исполняемый файл (тим файла 17-й байт!!);
   0 - EM_NONE = модель проца...  6 – Intel i486; 50 – Intel IA-64 Processor;
   0 - Elf32_Word  /* Номер версии */
   0x8048000 старт адрес - обычно для исполняемых... тип word
  }
  //BashScript (UNIX)
end;


procedure create_BATFile(fname:string);
begin
  //for windows
end;

end.


unit macro;

{$mode objfpc}{$H+}
//{$Define DEBUGMODE}

interface

uses
  Classes, SysUtils, mik_asm_compiller, asm_comp;// SynHighlighterAny;

const
  macr_file_addr='./macro.masm';   //расположение на физ носителе

type
  {макросы}
     TMacroPtr=^TMikMacros;

     TMikMacros=record
        name:TVarName;
        prm:string;
        body:Ansistring;

        MemTablePtr:TLVarTablePTR; //указатель на табл

        NextMacros:TMacroPtr;
     end;

     TMacrosList=object
     private
        First,Last:TMacroPtr;
        Fcount:byte;  //до 255 макросов....
     public
        property count:byte read Fcount;
        procedure ini_MacroList;
        procedure clean_macroList;
        function  getPtrToMacros(name:TVarName):TMacroPtr;
        function  AddNewMacros(name:TVarName; prm:string; var code:ansistring):boolean;
        procedure reload_macro_list;
        procedure CleanMemTables;
     end;

     var
       macros_list:TMacrosList;

  //procedure reload_macro_list;
  function proc_macro_code(call_prm:string; var table:TLVarTablePTR; var error_code:byte):Ansistring; //EXPEREMENTAL 30.03.16


implementation

{UTILS}
procedure TMacrosList.ini_MacroList;
begin
 first:=nil;
 last:=nil;
 Fcount:=0;
end;

procedure TMacrosList.clean_macroList;
var
  wrk_ptr:TMacroPtr;
begin
 with macros_list do
  while (First<>nil) do
     begin
        wrk_ptr:=First;
        first:=first^.nextMacros;
        dispose(wrk_ptr);
     end;

    ini_MacroList;
end;

function  TMacrosList.getPtrToMacros(name:TVarName):TMacroPtr;  //NEW 29.03.16
var
  wrk_ptr:TMacroPtr;
begin
  wrk_ptr:=macros_list.First;

     while ((wrk_ptr<>nil) and (wrk_ptr^.name<>name)) do
            wrk_ptr:=wrk_ptr^.NextMacros;
 //return
   getPtrToMacros:=wrk_ptr;
 end;

function  TMacrosList.AddNewMacros(name:TVarName; prm:string; var code:ansistring):boolean;  //код до max_macro_code_len
var
  new_el:TMacroPtr;
begin
 result:=false;
 name:=Uppercase(name);
 prm:=Uppercase(prm);

  if (macros_list.count<max_macros_count) then
  with macros_list do
       begin
          //поиск
          if (getPtrToMacros(name)=nil) then
              begin
                 new(new_el);
                 new_el^.NextMacros:=nil;
                 new_el^.name:=name;
                 new_el^.prm:=prm;
                 new_el^.body:=code;
                 new_el^.MemTablePtr:=nil;

                 //new_el^.id:=count;

                 {Задать маски переменным....."каждый уникален с рождения" }
                // SetMask2Vars(new_el^.code, genMask(new_el^.id, false));

                 //линковка
                 if (last<>nil) then last^.NextMacros:=new_el
                                else first:=new_el;
                 last:=new_el;

                 //finalization
                 inc(Fcount);
                 result:=true;

                 //добавим его в список "известных макросов редактору"
                 asm_code.ASM_style.Constants.Add(name);
              end;
       end;
end;

function  check_call_prm(src:string):boolean;  //25.03.16  (процедуры и ф-ии)
var
  prm:string;
begin
 check_call_prm:=true;

 if src[length(src)]=',' then check_call_prm:=false  //фикс лишней запятой в конце
 else
 if length(src)>0 then
  //ищем все переменные разделенные запятыми
      while (check_call_prm) and (length(src)>0) do
         begin
              cut_str_value(src,prm, ',');
              delete(src,1,1);
              check_call_prm:=check_prm(trim(prm))=0; //должен быть  = 0
         end;
end;

procedure TMacrosList.reload_macro_list;
var
  MacrFile:Text;
  Read_line,sub_line:string;
  ext_code:byte;

  state:(head,t_body,b_body);

  m_name,prm:string;
  code:ansistring;
begin
 //ini
 clean_macroList;
 {GUI!!}
 //asm_code.gui_macros_list.Clear;

 state:=head;
 ext_code:=0;
 asm_code.MacroGUITable.RowCount:=1;
 asm_code.ASM_style.Constants.Clear;

 //скан файла macr_file_addr:string; на макросы
 if FileExists(macr_file_addr) then
     begin
       assignFile(MacrFile, macr_file_addr);
       reset(MacrFile);

       while (not EOF(MacrFile)) do
           BEGIN
              //читай строку и обрабатывай
                readln(MacrFile, Read_line);
                trim(read_line);

                while length(Read_line)>0 do
                    BEGIN
                        //set state
                        if pos('macro ',lowercase(read_line))=1 then state:=head  //разве в нижнем только?
                                           else
                        if pos('{',read_line)=1 then begin state:=t_body; code:=''; delete(Read_line,1,1);  end
                                           else
                        if pos('}',read_line)=1 then begin state:=b_body; delete(Read_line,1,1); end;

                        //do this...

                        case State of
                             HEAD:
                                 begin
                                   //удалим "macro" и получим имя и параметры
                                   delete(read_line,1,6);
                                   cut_str_value(read_line,sub_line,'{');
                                   sub_line:=trim(sub_line);

                                   //получено: |<m_name>[(prms)]|
                                   cut_str_value(sub_line,m_name,'('); //имя
                                   m_name:=trim(m_name);
                                   //что осталось есть prm |( smb )|
                                   delete(sub_line,1,1);
                                   delete(sub_line,length(sub_line),1);
                                   prm:=trim(sub_line);
                                 end;
                             T_BODY:
                                 begin
                                   //найден { - начало тела макроса
                                   cut_str_value(read_line,sub_line,'}');
                                   code:=code+' '+trim(delete_comments(sub_line)); //подравняй и удали комментраии
                                 end;
                             B_BODY:
                                 begin

                                 if (check_prm(m_name)<>0) then ext_code:=11
                                                         else
                                 if (check_call_prm(prm)=false) then ext_code:=12
                                                              else
                                 if (trim(code)='') then ext_code:=13;


                                 if (ext_code=0) then //если коррекны имя и параметры, тело макроса не пусто!...
                                    gen_code_line(code, code, ext_code); //собери код  -> error 0/1

                                 if (ext_code=0) then
                                    if (AddNewMacros(m_name,prm,code)=false)  then ext_code:=14;
                                 {проверку на существование выполнит добавляюшая п/программа}

                                 //-----------пишем лог----------------
                                 with  asm_code.MacroGUITable do
                                 begin
                                     RowCount:=RowCount+1;
                                     Cells[1,RowCount-1]:=Uppercase(m_name+' ('+prm+')');

                                     case ext_code of
                                          0:Cells[2,RowCount-1]:='Загружен. Синтаксических ошибок не обнаружено.';
                                         11:Cells[2,RowCount-1]:='Ошибка: Неверно имя макроса (недопустимое имя идентификатора)';
                                         12:Cells[2,RowCount-1]:='Ошибка: Синтаксическая ошибка при описании формальных параметров';
                                         13:Cells[2,RowCount-1]:='Ошибка: Пустое тело макроса';
                                          1:Cells[2,RowCount-1]:='Ошибка: Синтаксическая ошибка в теле макроса';
                                         14:Cells[2,RowCount-1]:='Ошибка: Макрос '+m_name+' уже был ранее зарегестрирован';
                                     end;
                                 end;
                                           //  asm_code.gui_macros_list.Items.Add(Uppercase(m_name+' ('+prm+')'));

                                   {else в GUI сообщение!!!!}
                                 end;
                        end; //case end
           END;  //line loop
       end;  //main loop
     end;
end; //procedure end

function  proc_macro_code(call_prm:string; var table:TLVarTablePTR; var error_code:byte):Ansistring; {21.10.16 NOT TESTED}
var
  macr_prm:string;
  code_line:string;

  //для замены
  from_prm,to_prm:string;
  GVar_id:word;
  macro_ptr:TMacroPtr; //указатель на макрос
begin

 {$IFDEF DEBUGMODE}
     writeln('   ****ЗАГРУЗКА proc_macro_code');
 {$ENDIF}

   {err 4 - несоотв параметров
    err 5 - макрос не найден
    err 0 - all ok }


   {ini}
  proc_macro_code:='';
  table:=nil;

  //дай имя макроса #<...>
  delete(call_prm,1,pos('#',call_prm)); //drop #
  cut_str_value(call_prm,macr_prm, ' '); //в macr_prm имя макроса...
  call_prm:=trim(call_prm);

  {$IFDEF DEBUGMODE}
     writeln('Ищу макрос=',macr_prm+'|');
 {$ENDIF}


  //дай макрос
  macro_ptr:=macros_list.getPtrToMacros(macr_prm);

  if (macro_ptr=nil) then error_code:=5 //не найден
       else
         with macro_ptr^ do
            begin
              {таблица есть?}
              if (MemTablePtr=nil) then
              begin
                  new(MemTablePtr);
                  MemTablePtr^.ini;
              end
                else
              begin
                 {иначе это не первое исп-е, чистим temp}
                  MemTablePtr^.clear(temponary);
              end;

              {обязательно дай указатель на таблицу!}
              table:=MemTablePtr;

              code_line:=body; //получим код макроса
              macr_prm:=prm;  //получим параметрs от макроса

  {$IFDEF DEBUGMODE}
      writeln('*Найден: ',code_line, '**с параметрами=',macr_prm);
  {$ENDIF}

              {занести адреса переменных в temp таблицы, инф из стека...}
              REPEAT
                     cut_str_value(macr_prm,to_prm,',');  //дай параметры
                     cut_str_value(call_prm,from_prm,',');    //дай из "кода"
                     delete(macr_prm,1,1);
                     delete(call_prm,1,1);


                     {регистр сохранить!}
                     from_prm:=trim(from_prm);
                     to_prm:=trim(to_prm);

                     {найди переменную  FALSE оправдан?????????? }
                     if (Try2RegVar(from_prm, false, GVar_id)=0)
                        then begin
                           MemTablePtr^.add(to_prm, GVar_id, temponary); //только temponary
                            {$IFDEF DEBUGMODE}
                              writeln(Debugcode,' запись временной пер-й: ',to_prm,' с адресом=',GVar_id);
                            {$ENDIF}


                        end;


              UNTIL ((length(to_prm)=0) or (length(from_prm)=0));


              {Заменили, теперь:
               ***********************check**************************
               все ок = длинны обоих параметров по окончании цикла = 0}
               if (length(to_prm)+length(from_prm)=0) then error_code:=0
                                                      else error_code:=4; //несоответствие кол-ва переменных


               {finalization}
               proc_macro_code:=code_line;
               {$IFDEF DEBUGMODE}
               writeln('RETURNED=',proc_macro_code);
               {$ENDIF}
             end;
end;

procedure TMacrosList.CleanMemTables;
var
  macros:TMacroPtr;
begin
  macros:=First;
  while macros<>nil do
  begin
      if (macros^.MemTablePtr<>nil) then
       macros^.MemTablePtr^.ClearAll;
       macros:=macros^.NextMacros;
  end;
end;

begin
  macros_list.ini_MacroList;
end.

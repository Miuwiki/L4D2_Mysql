# L4D2 简易数据库
## 食用方法：
* database.cfg放入sourcemod/config文件夹内
* 根据需要，选择远程数据库（mysql），本地数据库（sqlite），请在driver处填写合适的引擎
* 打开数据库，创建miuwiki_l4d2数据库
* database.cfg里的user填写使用的数据库账户，pass填写使用的数据库密码
## NOTE：
* 注意检查你使用的user用户是否具有UPDATE，INSERT，SELECT等权限。
* 如果mysql版本在5.7以上，会发生 no default value 错误的情况。因为创建表使用了not null，严格模式不认可这种值。

1.找到：mysql/my.cnf

2.找到这一行：sql-model=STRICT_TRANS_TABLES,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION 

3.修改为：sql-mode=NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION

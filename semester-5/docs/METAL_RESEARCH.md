# Metal и техники компьютерной графики

Проверено 10.11.2026. Это журнал решений для текущей реализации, не обещание будущей актуальности.
Перед изменением API/техники повторно проверить первичные источники и установленный SDK.
База проекта остаётся macOS 26+, Apple Silicon, Swift 6, Metal 4; новые ОС и функции WWDC не
становятся обязательными без отдельного решения.

## Metal 4: применённые решения

| Тема | Первичный источник | Решение для движка и проверка |
|---|---|---|
| Command buffers/allocators и lifetime | [Metal 4 core API](https://developer.apple.com/documentation/metal/understanding-the-metal-4-core-api) | Три слота, reuse/reset после completion; сильное удержание GPU-ресурсов слотом. Тесты повторного использования и удаления меша до completion. |
| Resource hazards | [Resource synchronization](https://developer.apple.com/documentation/metal/resource-synchronization) | Residency не разрешает hazards. Явный consumer barrier между этапами; текущая широкая область — осознанный консервативный вариант. Тесты depth/output/readback. |
| Привязки | [MTL4ArgumentTable](https://developer.apple.com/documentation/metal/mtl4argumenttable) | Отдельные таблицы Forward/Output в каждом слоте. Индексы общие в GPUShared. Не переносить старые setVertexBuffer/useResource-паттерны в Metal 4 без проверки API. |
| Доступность allocations | [MTLResidencySet](https://developer.apple.com/documentation/metal/mtlresidencyset) | Pass-owned allocations добавляются до commit; set изменяется последовательно. Удержание объектов и residency — разные обязанности. Пользовательский проход проверен захватом своего буфера. |
| Представление drawable | [Explore Metal 4 games](https://developer.apple.com/videos/play/wwdc2025/254/) | Сохраняется waitForDrawable → queue commit → signalDrawable → present. Отсутствующий drawable не занимает слот. |
| Availability/ABI/MSL | [Metal resources: спецификация MSL и feature tables](https://developer.apple.com/metal/resources/) | Runtime-проверка Metal 4/sample counts, compile-time sizeof/alignment/offsetof. Версия API и версия языка шейдеров проверяются отдельно. |
| Измерения | [Find and fix performance issues, WWDC26](https://developer.apple.com/videos/play/wwdc2026/388/) | Разделять encode/wait/GPU/presentation и связывать данные с конфигурацией сцены. Новые средства ОС не добавлены в зависимости: локальная база — Xcode 26.6/macOS 26.5.2. |

При рефакторинге подготовка контрактов вынесена в RenderPipelinePlan, владение слотом — в FrameResources,
инструментирование — в RendererInstrumentation. Из этого анализа не следует, что barrier можно удалить
после добавления ресурса в residency set. Схема ресурсов, lifetime и синхронизация проверяются независимо.

## Текущие графические соглашения

Мир правосторонний, камера смотрит по −Z, векторы — столбцы. Положение вершины вычисляется как
`projection * view * model * position`; Metal device depth — 0…1, depth clear — 1, comparison — less.
Нормали преобразуются inverse-transpose матрицей модели и нормализуются в fragment stage.
Невырожденность модели проверяется до upload. Эти соглашения проверены camera/depth тестами.

Forward пишет linear RGB в RGBA16Float HDR. Свет — учебное направленное diffuse-приближение
с постоянным ambient, без физической нормировки BRDF, теней и непрямого освещения.
Output применяет multiplier exposure и `c / (1 + c)`; sRGB render target кодирует результат.
Debugger показывает исходные значения отдельно от tone-mapped preview. Цвет должен иметь определённое
пространство; нельзя трактовать RGB-тройку как универсальное описание цвета.
[PBRT 4: Color](https://pbr-book.org/4ed/Radiometry,_Spectra,_and_Color/Color)
объясняет связь спектральных данных, XYZ и RGB-пространств.

MSAA хранит отдельные multisample attachments и resolve в HDR. В обычном режиме цвет разрешается
через multisampleResolve; при capture исходные samples сохраняются для инспекции. GPU-тест проверяет
samples цвета и глубины. Автоматическое превращение этих ресурсов в memoryless нарушило бы readback.
У Apple GPU tile-based архитектура даёт другие компромиссы по bandwidth и store/load, чем на desktop
immediate renderer; это следует учитывать до введения G-buffer и дополнительных полноэкранных проходов.
[Apple: tile-based deferred rendering](https://developer.apple.com/documentation/metal/tailor-your-apps-for-apple-gpus-and-tile-based-deferred-rendering)
служит исходной точкой анализа, а не основанием автоматически менять архитектуру на deferred.

## Как исследовать следующую технику

Для PBR начать с [PBRT 4: Microfacet theory](https://www.pbr-book.org/4ed/Reflection_Models/Roughness_Using_Microfacet_Theory):
согласованно определить normal distribution, masking/shadowing, Fresnel, roughness и энергетические
ограничения. Нельзя назвать произвольный diffuse+specular шейдер физически корректным только из-за GGX.
Для теней отдельно исследовать проекцию/precision/bias и фильтрацию; для temporal-техник — history,
motion vectors и invalidation; для deferred — стоимость G-buffer и tile memory. Эти возможности пока не реализованы.

Для каждой задачи сохранить короткую запись: дата и SDK → URL первоисточника → формулы/соглашения →
требования GPU/форматы → стоимость CPU/GPU/памяти → выбранное расширение → тестовая сцена →
результат сравнения изображения и профиля. При расхождении примера из статьи с SDK проверить заголовки
и минимальный компилируемый пример. Ссылки и изучение техники дополняют GPU-тест, но не заменяют его.

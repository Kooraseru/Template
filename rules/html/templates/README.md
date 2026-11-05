# HTML templates and localization

A template is authored source. The generated page is output. Make dynamic
insertion points recognizable, validate required values during the build, and
escape inserted content for its destination context. Do not hand-edit output
to repair a template.

Keep each piece of user-facing text in the owning content or localization
catalog. Locale metadata has one declaration owner; templates and browser code
derive their options from it rather than repeating supported-language lists.
The default locale must be complete so it can render meaningful HTML before
client code runs. Missing optional translations may fall back according to the
catalog contract. Do not create separate locale routes when the product contract
calls for one route with in-place language changes.

Keep content data separate from interface copy when they have different
ownership. A project record, for example, may own its translated title while
the interface catalog owns the label on its button. Attribute translations
must update the intended attribute, including accessible names; a generic
text replacement must not silently write to the wrong destination.


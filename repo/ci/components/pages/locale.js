(() => {
	const data = window.__PAGE_I18N__;
	if (!data || !data.locales) return;
	const locales = data.locales;
	const available = Object.keys(locales);
	if (available.length === 0) return;

	function apply(locale) {
		const selected = locales[locale];
		if (!selected) return;
		for (const element of document.querySelectorAll("[data-i18n]")) {
			const value = selected.tags[element.dataset.i18n];
			if (value !== undefined) element.textContent = value;
		}
		if (selected.tags.page_title) document.title = selected.tags.page_title;
		document.documentElement.lang = locale;
	}

	function readPreference() {
		const entry = document.cookie.split("; ").find((value) => value.startsWith("site_locale="));
		if (!entry) return data.defaultLocale;
		const value = decodeURIComponent(entry.slice("site_locale=".length));
		return locales[value] ? value : data.defaultLocale;
	}

	const toggle = document.createElement("button");
	toggle.type = "button";
	toggle.textContent = "Language / 言語";
	toggle.setAttribute("aria-haspopup", "dialog");
	toggle.style.cssText = "position:fixed;right:1rem;top:1rem;z-index:1000;padding:.55rem .8rem;cursor:pointer";

	const dialog = document.createElement("dialog");
	const heading = document.createElement("h2");
	heading.textContent = "Choose a language / 言語を選択";
	const select = document.createElement("select");
	select.setAttribute("aria-label", "Language / 言語");
	for (const locale of available) {
		const option = document.createElement("option");
		option.value = locale;
		option.textContent = locales[locale].name;
		select.append(option);
	}
	const save = document.createElement("button");
	save.type = "button";
	save.textContent = "Save / 保存";
	const cancel = document.createElement("button");
	cancel.type = "button";
	cancel.textContent = "Cancel / キャンセル";
	const actions = document.createElement("p");
	actions.append(save, " ", cancel);
	dialog.append(heading, select, actions);
	document.body.prepend(toggle, dialog);

	const current = readPreference();
	select.value = current;
	apply(current);
	toggle.addEventListener("click", () => dialog.showModal());
	cancel.addEventListener("click", () => dialog.close());
	save.addEventListener("click", () => {
		const locale = select.value;
		document.cookie = `site_locale=${encodeURIComponent(locale)}; Path=/; Max-Age=31536000; SameSite=Lax`;
		apply(locale);
		dialog.close();
	});
})();
